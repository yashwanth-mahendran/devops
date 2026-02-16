resource "aws_ssm_parameter" "devops_packages" {
  name        = "/${var.project_name}/packages/devops"
  description = "DevOps packages and repositories"
  type        = "String"
  value = jsonencode({
    docker = {
      repo    = "https://github.com/docker/docker-ce.git"
      version = "latest"
    }
    kubernetes = {
      kubectl = "https://dl.k8s.io/release/stable.txt"
      helm    = "https://get.helm.sh/helm-latest-linux-amd64.tar.gz"
      k9s     = "https://github.com/derailed/k9s/releases/latest"
      eksctl  = "https://github.com/weaveworks/eksctl/releases/latest"
    }
    terraform = {
      repo    = "https://releases.hashicorp.com/terraform"
      version = var.terraform_version
    }
    ansible = {
      repo    = "https://github.com/ansible/ansible.git"
      install = "pip3 install ansible"
    }
    jenkins = {
      repo = "https://pkg.jenkins.io/redhat-stable/"
      cli  = "pip3 install jenkins-cli"
    }
    trivy = {
      repo    = "https://github.com/aquasecurity/trivy"
      version = var.trivy_version
    }
  })

  tags = {
    Name = "${var.project_name}-devops-packages"
  }
}

resource "aws_ssm_parameter" "mlops_packages" {
  name        = "/${var.project_name}/packages/mlops"
  description = "MLOps packages and repositories"
  type        = "String"
  value = jsonencode({
    python = {
      version = var.python_version
      packages = [
        "mlflow",
        "dvc",
        "kubeflow-pipelines",
        "tensorflow",
        "pytorch",
        "scikit-learn",
        "pandas",
        "numpy",
        "jupyter",
        "jupyterlab",
        "matplotlib",
        "seaborn",
        "plotly"
      ]
    }
    mlflow = {
      repo    = "https://github.com/mlflow/mlflow.git"
      install = "pip3 install mlflow"
      version = "latest"
    }
    dvc = {
      repo    = "https://github.com/iterative/dvc.git"
      install = "pip3 install dvc[all]"
      version = "latest"
    }
    kubeflow = {
      repo     = "https://github.com/kubeflow/kubeflow.git"
      pipelines = "https://github.com/kubeflow/pipelines.git"
      install  = "pip3 install kfp"
    }
    ray = {
      repo    = "https://github.com/ray-project/ray.git"
      install = "pip3 install ray[default]"
    }
    feast = {
      repo    = "https://github.com/feast-dev/feast.git"
      install = "pip3 install feast"
    }
    bentoml = {
      repo    = "https://github.com/bentoml/BentoML.git"
      install = "pip3 install bentoml"
    }
    seldon = {
      repo = "https://github.com/SeldonIO/seldon-core.git"
      cli  = "pip3 install seldon-core"
    }
  })

  tags = {
    Name = "${var.project_name}-mlops-packages"
  }
}

resource "aws_ssm_parameter" "programming_languages" {
  name        = "/${var.project_name}/packages/languages"
  description = "Programming language versions and repositories"
  type        = "String"
  value = jsonencode({
    python = {
      version = var.python_version
      repo    = "https://www.python.org/downloads/"
    }
    java = {
      version = var.java_version
      repo    = "https://docs.aws.amazon.com/corretto/"
    }
    nodejs = {
      version = var.nodejs_version
      repo    = "https://nodejs.org/en/download/"
    }
    maven = {
      version = var.maven_version
      repo    = "https://maven.apache.org/download.cgi"
    }
  })

  tags = {
    Name = "${var.project_name}-languages"
  }
}

resource "aws_ssm_parameter" "installation_script" {
  name        = "/${var.project_name}/scripts/install-mlops"
  description = "MLOps packages installation script"
  type        = "String"
  value       = <<-EOF
#!/bin/bash
set -e

echo "Installing MLOps packages..."

# Install Python ML packages
pip3 install --upgrade pip
pip3 install mlflow dvc kubeflow-pipelines tensorflow torch scikit-learn pandas numpy jupyter jupyterlab matplotlib seaborn plotly

# Install Ray
pip3 install ray[default]

# Install Feast
pip3 install feast

# Install BentoML
pip3 install bentoml

# Install Seldon Core
pip3 install seldon-core

echo "MLOps packages installed successfully!"
EOF

  tags = {
    Name = "${var.project_name}-mlops-install-script"
  }
}
