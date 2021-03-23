
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
        stage("Install"){
            steps{
                sh 'python setup.py install --user'
            }
        }
    }
}