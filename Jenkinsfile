
pipeline {
    agent{
        dockerfile{
            filename 'Dockerfile'
        }
    }
    stages{
        stage("Build"){
            steps{
                sh 'python setup.py'
            }
        }
        stage("Install"){
            steps{
                sh 'pip install .'
            }
        }
    }
}