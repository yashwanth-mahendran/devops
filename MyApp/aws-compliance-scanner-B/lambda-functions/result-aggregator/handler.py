"""
Result Aggregator Lambda
Called by Step Functions after all compliance checks complete.
Flattens nested Map state results and writes to DynamoDB.
"""
import boto3
import json
import logging
import os
from typing import Any, Dict, List

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
results_table = dynamodb.Table(os.environ.get("DYNAMODB_RESULTS_TABLE", "compliance-scan-results"))


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Aggregate results from Step Functions Map state.
    
    Input structure (from nested Maps):
    {
        "job_id": "...",
        "account_results": [
            [  # Per account
                [  # Per region
                    [  # Per check
                        {"check_id": "...", "status": "PASSED", ...}
                    ]
                ]
            ]
        ]
    }
    
    Output:
    {
        "total": 100,
        "passed": 85,
        "failed": 10,
        "errors": 5
    }
    """
    job_id = event["job_id"]
    account_results = event.get("account_results", [])
    
    logger.info(f"Aggregating results for job_id={job_id}")
    
    # Flatten nested arrays
    flattened_results = []
    
    def flatten(data):
        """Recursively flatten nested lists."""
        if isinstance(data, list):
            for item in data:
                flatten(item)
        elif isinstance(data, dict):
            if "check_id" in data or "status" in data:
                flattened_results.append(data)
            else:
                # Might be a nested structure with results
                for value in data.values():
                    if isinstance(value, (list, dict)):
                        flatten(value)
    
    flatten(account_results)
    
    logger.info(f"Flattened {len(flattened_results)} results")
    
    # Count statuses
    passed = 0
    failed = 0
    errors = 0
    
    # Batch write to DynamoDB
    with results_table.batch_writer() as batch:
        for result in flattened_results:
            status = result.get("status", "ERROR")
            
            if status == "PASSED":
                passed += 1
            elif status == "FAILED":
                failed += 1
            else:
                errors += 1
            
            # Build DynamoDB item
            item = {
                "pk": job_id,
                "sk": f"{result.get('check_id', 'unknown')}#{result.get('account_id', 'unknown')}#{result.get('region', 'unknown')}",
                "job_id": job_id,
                "check_id": result.get("check_id", "unknown"),
                "account_id": result.get("account_id", "unknown"),
                "region": result.get("region", "unknown"),
                "status": status,
                "message": result.get("message", ""),
                "resource_id": result.get("resource_id", ""),
                "remediation": result.get("remediation", ""),
            }
            
            batch.put_item(Item=item)
    
    total = passed + failed + errors
    logger.info(f"Job {job_id} complete: total={total}, passed={passed}, failed={failed}, errors={errors}")
    
    return {
        "total": total,
        "passed": passed,
        "failed": failed,
        "errors": errors,
    }
