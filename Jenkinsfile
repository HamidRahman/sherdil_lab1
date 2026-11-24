pipeline {
  agent any

  options {
    timestamps()
    timeout(time: 30, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
    disableConcurrentBuilds()
  }

  environment {
    // ---- AWS / ECR ----
    AWS_REGION  = 'us-east-1'
    ACCOUNT_ID  = '678878256416'
    ECR_REPO    = 'hamidr/repo_1'
    REGISTRY    = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    IMAGE_TAG   = "${env.BUILD_NUMBER}"
    IMAGE_URI   = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${env.BUILD_NUMBER}"

    // ---- ECS (EC2 launch type) ----
    CLUSTER     = 'hamidR-task31-cluster'
    SERVICE     = 'hamidR-Task-Definition-Task31-service-ygwwjdgx'
    TASK_FAMILY = 'hamidR-Task-Definition-Task31'
    CONTAINER   = 'app'

    // ---- Smoke test ----
    ALB_DNS     = 'http://hamidr-lb-19152452.us-east-1.elb.amazonaws.com/'
    HEALTH_PATH = '/health'
  }

  stages {

    stage('Preflight') {
      steps {
        sh '''
          set -e
          for bin in docker aws jq curl; do
            command -v $bin >/dev/null 2>&1 || { echo "MISSING: $bin is not installed on the Jenkins agent"; exit 1; }
          done
          echo "Caller identity:"
          aws sts get-caller-identity --output table
        '''
      }
    }

    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Login to ECR') {
      steps {
        sh '''
          set -e
          aws ecr get-login-password --region $AWS_REGION \
            | docker login --username AWS --password-stdin $REGISTRY
        '''
      }
    }

    stage('Build image') {
      steps {
        script {
          env.GIT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
        }
        sh '''
          set -e
          docker build \
            --build-arg BUILD_NUMBER=$IMAGE_TAG \
            --build-arg GIT_SHA=$GIT_SHA \
            --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            -t $IMAGE_URI .
        '''
      }
    }

    stage('Push to ECR') {
      steps {
        sh '''
          set -e
          docker push $IMAGE_URI
        '''
      }
    }

    stage('Verify image in ECR') {
      steps {
        sh '''
          set -e
          aws ecr describe-images \
            --repository-name $ECR_REPO \
            --image-ids imageTag=$IMAGE_TAG \
            --region $AWS_REGION \
            --query 'imageDetails[0].{tag:imageTags[0],pushedAt:imagePushedAt,sizeBytes:imageSizeInBytes}' \
            --output table
        '''
      }
    }

    stage('Capture current revision') {
      steps {
        script {
          env.PREVIOUS_TD = sh(
            script: '''
              aws ecs describe-services \
                --cluster $CLUSTER --services $SERVICE --region $AWS_REGION \
                --query 'services[0].taskDefinition' --output text
            ''',
            returnStdout: true
          ).trim()
          echo "Rollback target if this deploy fails: ${env.PREVIOUS_TD}"
        }
      }
    }

    stage('Register task definition') {
      steps {
        sh '''
          set -e

          aws ecs describe-task-definition \
            --task-definition $TASK_FAMILY \
            --region $AWS_REGION \
            --query 'taskDefinition' > taskdef.json

          # Swap the image on our container; strip only the read-only fields.
          # networkMode (bridge) and requiresCompatibilities (EC2) are deliberately KEPT.
          jq --arg IMG "$IMAGE_URI" --arg C "$CONTAINER" '
            .containerDefinitions |= map(if .name == $C then .image = $IMG else . end)
            | del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
                  .compatibilities, .registeredAt, .registeredBy, .deregisteredAt)
          ' taskdef.json > new-taskdef.json

          # Fail loudly if the container name never matched.
          grep -q "$IMAGE_URI" new-taskdef.json || {
            echo "ERROR: container '$CONTAINER' not found in task definition '$TASK_FAMILY'"
            jq -r '.containerDefinitions[].name' taskdef.json
            exit 1
          }

          NEW_TD=$(aws ecs register-task-definition \
            --cli-input-json file://new-taskdef.json \
            --region $AWS_REGION \
            --query 'taskDefinition.taskDefinitionArn' --output text)

          echo "$NEW_TD" > new-td-arn.txt
          echo "Registered: $NEW_TD"
        '''
        script {
          env.NEW_TD = readFile('new-td-arn.txt').trim()
        }
      }
    }

    stage('Deploy to ECS (EC2)') {
      steps {
        sh '''
          set -e

          aws ecs update-service \
            --cluster $CLUSTER \
            --service $SERVICE \
            --task-definition $NEW_TD \
            --region $AWS_REGION \
            --query 'service.{service:serviceName,desired:desiredCount,taskDef:taskDefinition}' \
            --output table

          echo "Waiting for the service to reach a steady state..."
          aws ecs wait services-stable \
            --cluster $CLUSTER --services $SERVICE --region $AWS_REGION

          echo "Steady state reached."
        '''
      }
    }

    stage('Smoke test') {
      when { expression { env.ALB_DNS != 'REPLACE-WITH-YOUR-ALB-DNS-NAME' } }
      steps {
        sh '''
          set -e
          for i in $(seq 1 10); do
            if curl -fsS "http://$ALB_DNS$HEALTH_PATH" >/dev/null; then
              echo "Smoke test passed on attempt $i"
              exit 0
            fi
            echo "Attempt $i failed, retrying in 10s..."
            sleep 10
          done
          echo "Smoke test failed against http://$ALB_DNS$HEALTH_PATH"
          exit 1
        '''
      }
    }
  }

  post {
    failure {
      script {
        echo '--- Last 10 service events ---'
        sh '''
          aws ecs describe-services \
            --cluster $CLUSTER --services $SERVICE --region $AWS_REGION \
            --query 'services[0].events[0:10].[createdAt,message]' \
            --output table || true
        '''
        if (env.PREVIOUS_TD?.trim() && env.NEW_TD?.trim() && env.PREVIOUS_TD != env.NEW_TD) {
          echo "Rolling back to ${env.PREVIOUS_TD}"
          sh '''
            aws ecs update-service \
              --cluster $CLUSTER --service $SERVICE \
              --task-definition $PREVIOUS_TD --region $AWS_REGION >/dev/null || true
            aws ecs wait services-stable \
              --cluster $CLUSTER --services $SERVICE --region $AWS_REGION || true
          '''
          echo 'Rollback complete.'
        }
      }
    }
    success {
      echo "Deployed ${env.IMAGE_URI} to ${env.SERVICE} on ${env.CLUSTER}"
    }
    always {
      sh 'docker image prune -f || true'
    }
  }
}
