pipeline {
    agent any

    environment {
        AWS_REGION = 'us-east-1'
        ACCOUNT_ID = '678878256416'
        REPO_NAME  = 'hamidr/test_repo_1'
        REGISTRY   = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        IMAGE_TAG  = "v${BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            steps { checkout scm }
        }

        stage('Build Image') {
          steps {
                script {
                  env.GIT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                }
                sh '''
                  docker build \
                    --build-arg BUILD_NUMBER=$IMAGE_TAG \
                    --build-arg GIT_SHA=$GIT_SHA \
                    --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                    -t $ECR_REPO:$IMAGE_TAG .
                '''
              }
        }

        stage('Login to ECR') {
            steps {
                sh '''
                  aws ecr get-login-password --region $AWS_REGION \
                  | docker login --username AWS --password-stdin $REGISTRY
                '''
            }
        }

        stage('Tag & Push') {
            steps {
                sh '''
                  docker tag $REPO_NAME:$IMAGE_TAG $REGISTRY/$REPO_NAME:$IMAGE_TAG
                  docker tag $REPO_NAME:$IMAGE_TAG $REGISTRY/$REPO_NAME:latest
                  docker push $REGISTRY/$REPO_NAME:$IMAGE_TAG
                  docker push $REGISTRY/$REPO_NAME:latest
                '''
            }
        }
    }

    post {
        always {
            sh 'docker rmi $REGISTRY/$REPO_NAME:$IMAGE_TAG $REGISTRY/$REPO_NAME:latest || true'
            sh 'docker logout $REGISTRY || true'
        }
        success { echo "Pushed $REGISTRY/$REPO_NAME:$IMAGE_TAG" }
    }
}
