pipeline {
    agent any
    environment {
        PYTHONUNBUFFERED = '1'
        DOCKER_IMAGE_NAME = 'library-management-platform'
        IMAGE_TAG = "v1.0.0"
        KUBECONFIG = '/var/lib/jenkins/.kube/config'
    }
    stages {
        stage('SCM Checkout') {
            steps {
                echo 'Checking out source code...'
                checkout scm
            }
        }
        stage('Environment Setup & Dependencies') {
            steps {
                echo 'Setting up Python environment and packages...'
                sh '''
                    python3 -m venv venv
                    . venv/bin/activate
                    pip install --upgrade pip
                    pip install -r requirements.txt
                '''
            }
        }
        stage('Code Linting & Syntax Gate') {
            steps {
                echo 'Checking code style with flake8...'
                sh '''
                    . venv/bin/activate
                    flake8 app/ database/ --count --select=E9,F63,F7,F82 --show-source --statistics
                '''
            }
        }
        stage('Automated Unit & Integration Tests') {
            steps {
                echo 'Running pytest...'
                sh '''
                    . venv/bin/activate
                    mkdir -p reports
                    pytest -v --cov=app --junitxml=reports/test-results.xml tests/
                '''
            }
        }
        stage('Build Docker Artifact') {
            steps {
                echo "Building Docker image ${DOCKER_IMAGE_NAME}:${IMAGE_TAG}..."
                sh '''
                    eval $(minikube -p minikube docker-env) || true
                    docker build -t ${DOCKER_IMAGE_NAME}:${IMAGE_TAG} .
                    docker tag ${DOCKER_IMAGE_NAME}:${IMAGE_TAG} ${DOCKER_IMAGE_NAME}:latest
                '''
            }
        }
        stage('Kubernetes Minikube Deployment') {
            steps {
                echo 'Applying Kubernetes manifests...'
                sh '''
                    kubectl apply -f k8s/deployment.yaml
                    kubectl apply -f k8s/service.yaml
                    kubectl rollout status deployment/library-deployment --timeout=90s
                '''
            }
        }
    }
    post {
        always {
            junit allowEmptyResults: true, testResults: 'reports/test-results.xml'
        }
        success {
            echo "CI/CD Pipeline executed successfully!"
        }
        failure {
            echo "Build failed. Check console output."
        }
    }
}
