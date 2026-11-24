pipeline {
  agent any
  options { timestamps() }

  environment {
    AWS_REGION = 'us-east-1'
    ACCOUNT_ID = '678878256416'
    ECR_REPO   = 'hamidr/repo_1'
    REGISTRY   = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    IMAGE_TAG  = "${env.BUILD_NUMBER}"
    IMAGE_URI  = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/hamidr/repo_1:${env.BUILD_NUMBER}"
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Login to ECR') {
      steps {
        sh '''
          aws ecr get-login-password --region $AWS_REGION \
            | docker login --username AWS --password-stdin $REGISTRY
        '''
      }
    }

    stage('Ensure ECR repository') {
      steps {
        sh '''
          aws ecr describe-repositories --repository-names $ECR_REPO --region $AWS_REGION >/dev/null 2>&1 \
            || aws ecr create-repository --repository-name $ECR_REPO \
                 --image-scanning-configuration scanOnPush=true --region $AWS_REGION
        '''
      }
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
            -t $IMAGE_URI .
        '''
      }
    }

    stage('Push to ECR') {
      steps {
        sh 'docker push $IMAGE_URI'
      }
    }

    stage('Verify image in ECR') {
      steps {
        sh '''
          aws ecr describe-images --repository-name $ECR_REPO \
            --image-ids imageTag=$IMAGE_TAG --region $AWS_REGION \
            --query 'imageDetails[0].{tag:imageTags[0],pushedAt:imagePushedAt,sizeMB:imageSizeInBytes}' \
            --output table
        '''
      }
    }
  }

  post {
    always  { sh 'docker image prune -f || true' }
    success {
      echo "=============================================================="
      echo " Image pushed. Paste this into your ECS task definition JSON:"
      echo "   \"image\": \"${IMAGE_URI}\""
      echo "=============================================================="
    }
    failure { echo "Build failed — check the ECR login and IAM permissions on the Jenkins instance role." }
  }
}
