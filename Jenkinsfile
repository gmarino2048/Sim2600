
pipeline {
    agent{
        dockerfile{
            filename 'Dockerfile'
        }
    }
    stages{
        stage("Build"){
            steps{
                sh 'python setup.py build'
            }
        }
    }
}