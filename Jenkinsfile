pipeline {
    agent any

    environment {
        PYTHONUNBUFFERED = '1'
        DOCKER_IMAGE_NAME = 'library-management-platform'
        IMAGE_TAG = 'v1.0.1'
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
                sh '''
                    python3 -m venv venv
                    . venv/bin/activate
                    pip install -r requirements.txt
                '''
            }
        }

        stage('Code Linting & Syntax Gate') {
            steps {
                sh '''
                    . venv/bin/activate
                    flake8 app/ database/ --count \
                      --select=E9,F63,F7,F82 \
                      --show-source --statistics
                    python -m compileall -q app database run.py
                '''
            }
        }

        stage('Automated Unit & Integration Tests') {
            steps {
                sh '''
                    . venv/bin/activate
                    mkdir -p reports
                    pytest -v --cov=app \
                      --junitxml=reports/test-results.xml tests/
                '''
            }
        }

        stage('Build Docker Artifact') {
            steps {
                sh '''
                    docker build \
                      -t ${DOCKER_IMAGE_NAME}:${IMAGE_TAG} .
                    docker tag \
                      ${DOCKER_IMAGE_NAME}:${IMAGE_TAG} \
                      ${DOCKER_IMAGE_NAME}:latest
                    minikube image load \
                      ${DOCKER_IMAGE_NAME}:${IMAGE_TAG}
                '''
            }
        }

        stage('Kubernetes Minikube Deployment') {
            steps {
                sh '''
                    kubectl apply -f k8s/deployment.yaml
                    kubectl apply -f k8s/service.yaml
                    kubectl rollout status \
                      deployment/library-deployment --timeout=120s
                    kubectl get pods
                '''
            }
        }
    }

    post {
        always {
            junit allowEmptyResults: true,
                  testResults: 'reports/test-results.xml'
        }
        success {
            echo 'CI/CD pipeline executed successfully!'
        }
        failure {
            echo 'Build failed. Check the Jenkins console output.'
        }
    }
}
