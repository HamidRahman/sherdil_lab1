pipeline {
  agent any

  environment {
    AWS_REGION  = 'us-east-1'
    ACCOUNT_ID  = '678878256416'
    ECR_REPO    = 'hamidr/ecr_repo1'
    REGISTRY    = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    IMAGE_TAG   = "${env.BUILD_NUMBER}"
    CLUSTER     = 'hamidR-task30-cluster'
    SERVICE     = 'hamidR-scenario30-task-service-q333ed2a'
    TASK_FAMILY = 'hamidR-scenario30-task'
    CONTAINER   = 'app'
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build image') {
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

    stage('Push to ECR') {
      steps {
        sh '''
          docker tag $ECR_REPO:$IMAGE_TAG $REGISTRY/$ECR_REPO:$IMAGE_TAG
          docker push $REGISTRY/$ECR_REPO:$IMAGE_TAG
        '''
      }
    }

    stage('Deploy to Fargate') {
      steps {
        sh '''
          NEW_IMAGE=$REGISTRY/$ECR_REPO:$IMAGE_TAG

          aws ecs describe-task-definition \
            --task-definition $TASK_FAMILY \
            --region $AWS_REGION \
            --query 'taskDefinition' > taskdef.json

          jq --arg IMG "$NEW_IMAGE" --arg C "$CONTAINER" '
            .containerDefinitions |= map(if .name == $C then .image = $IMG else . end)
            | del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
                  .compatibilities, .registeredAt, .registeredBy, .deregisteredAt)
          ' taskdef.json > new-taskdef.json

          REV=$(aws ecs register-task-definition \
            --cli-input-json file://new-taskdef.json \
            --region $AWS_REGION \
            --query 'taskDefinition.taskDefinitionArn' --output text)

          aws ecs update-service \
            --cluster $CLUSTER --service $SERVICE \
            --task-definition $REV --region $AWS_REGION

          aws ecs wait services-stable \
            --cluster $CLUSTER --service $SERVICE --region $AWS_REGION
        '''
      }
    }
  }

  post {
    always  { sh 'docker image prune -f || true' }
    success { echo "Deployed $REGISTRY/$ECR_REPO:$IMAGE_TAG to $SERVICE" }
  }
}
