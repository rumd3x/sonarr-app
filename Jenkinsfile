pipeline {
    agent {
        docker {
            image 'ghcr.io/cirruslabs/flutter:latest'
            label 'docker'
        }
    }
    
    parameters {
        choice(
            name: 'RELEASE_TYPE',
            choices: ['patch', 'minor', 'major'],
            description: 'Type of version increment (patch: 1.0.0 -> 1.0.1, minor: 1.0.0 -> 1.1.0, major: 1.0.0 -> 2.0.0)'
        )
        text(
            name: 'RELEASE_NOTES',
            defaultValue: '',
            description: 'Release notes for this version (will be included in Forgejo and Play Store releases)'
        )
        booleanParam(
            name: 'PUBLISH_TO_PLAY_STORE',
            defaultValue: true,
            description: 'Publish to Google Play Store (requires Play Store credentials configured)'
        )
        choice(
            name: 'PLAY_STORE_TRACK',
            choices: ['production', 'beta', 'alpha', 'internal'],
            description: 'Play Store release track (only used when PUBLISH_TO_PLAY_STORE is enabled; internal = safe for testing, production = public release)'
        )
        choice(
            name: 'PLAY_STORE_RELEASE_STATUS',
            choices: ['completed', 'draft'],
            description: 'Release status (draft = requires manual review in Play Console, completed = goes live immediately on selected track). Use DRAFT for apps not yet published.'
        )
    }
    
    environment {
        FORGEJO_CREDENTIALS_ID = 'forgejo-credentials'  // Jenkins "secret text" credential holding a Forgejo access token (write:repository)
        FORGEJO_HOST = 'forgejo.rumd3x.com'
        FORGEJO_REPO = 'Arr/sonarr-app'  // Forgejo mirrors pushes to GitHub automatically
        GIT_BRANCH_NAME = 'master'  // Branch that receives the version bump commit
        APP_NAME = 'sonarr'
        PLAY_STORE_CREDENTIALS_ID = 'play-store-service-account'  // Jenkins credential ID for Play Store JSON key
        ANDROID_KEYSTORE_ID = 'android-upload-keystore'  // Jenkins credential ID for keystore file
        ANDROID_KEYSTORE_PASSWORD_ID = 'android-keystore-password'  // Jenkins credential ID for keystore password
    }
    
    stages {
        stage('Checkout') {
            steps {
                echo 'Checking out source code...'
                checkout scm
                
                // Configure git user for commits
                sh '''
                    git config user.name "Jenkins CI"
                    git config user.email "jenkins@ci.local"
                '''
            }
        }
        
        stage('Setup Android Signing') {
            steps {
                script {
                    echo 'Setting up Android signing configuration...'
                    
                    withCredentials([
                        file(credentialsId: env.ANDROID_KEYSTORE_ID, variable: 'KEYSTORE_FILE'),
                        string(credentialsId: env.ANDROID_KEYSTORE_PASSWORD_ID, variable: 'KEYSTORE_PASSWORD')
                    ]) {
                        // Copy keystore to expected location
                        sh 'cp $KEYSTORE_FILE android/upload-keystore.jks'
                        
                        // Create key.properties file
                        sh """
                            cat > android/key.properties << EOF
storePassword=${KEYSTORE_PASSWORD}
keyPassword=${KEYSTORE_PASSWORD}
keyAlias=upload
storeFile=\${PWD}/android/upload-keystore.jks
EOF
                        """
                        
                        echo 'Android signing configured successfully'
                    }
                }
            }
        }
        
        stage('Calculate New Version') {
            steps {
                script {
                    echo "Release type: ${params.RELEASE_TYPE}"
                    
                    // Extract current version from pubspec.yaml
                    def versionLine = sh(
                        script: "grep '^version:' pubspec.yaml | head -1",
                        returnStdout: true
                    ).trim()
                    
                    def versionMatch = (versionLine =~ /version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)/)
                    if (!versionMatch) {
                        error("Could not parse version from pubspec.yaml")
                    }
                    
                    def major = versionMatch[0][1] as Integer
                    def minor = versionMatch[0][2] as Integer
                    def patch = versionMatch[0][3] as Integer
                    def build = versionMatch[0][4] as Integer
                    
                    def currentVersion = "${major}.${minor}.${patch}"
                    echo "Current version: ${currentVersion}+${build}"
                    
                    // Calculate new version based on release type
                    switch(params.RELEASE_TYPE) {
                        case 'major':
                            major++
                            minor = 0
                            patch = 0
                            break
                        case 'minor':
                            minor++
                            patch = 0
                            break
                        case 'patch':
                            patch++
                            break
                    }
                    
                    // Increment build number
                    build++
                    
                    def newVersion = "${major}.${minor}.${patch}"
                    env.NEW_VERSION = newVersion
                    env.NEW_BUILD_NUMBER = build.toString()
                    env.VERSION_TAG = "v${newVersion}"
                    
                    echo "New version will be: ${newVersion}+${build}"
                    echo "Git tag will be: ${env.VERSION_TAG}"
                }
            }
        }
        
        stage('Update Version') {
            steps {
                echo "Updating version to ${env.NEW_VERSION}+${env.NEW_BUILD_NUMBER}..."
                
                // Make sure script is executable
                sh 'chmod +x scripts/update_version.sh'
                
                // Run version update script
                sh "./scripts/update_version.sh ${env.NEW_VERSION} ${env.NEW_BUILD_NUMBER}"
                
                // Verify the update
                sh 'cat pubspec.yaml | grep "^version:"'
            }
        }
        
        stage('Get Dependencies') {
            steps {
                echo 'Fetching Flutter dependencies...'
                sh 'flutter pub get'
            }
        }
        
        stage('Analyze & Test') {
            steps {
                echo 'Running static analysis and unit tests...'
                sh 'flutter analyze'
                sh 'flutter test'
            }
        }
        
        stage('Build Release APK') {
            steps {
                echo "Building release APK for version ${env.NEW_VERSION}+${env.NEW_BUILD_NUMBER}..."
                sh "flutter build apk --release"
                
                // Rename APK with version number
                sh """
                    cd build/app/outputs/flutter-apk/
                    cp app-release.apk ${env.APP_NAME}-${env.NEW_VERSION}-${env.NEW_BUILD_NUMBER}.apk
                    ls -lh *.apk
                """
            }
        }
        
        stage('Build App Bundle (AAB)') {
            when {
                expression { params.PUBLISH_TO_PLAY_STORE == true }
            }
            steps {
                echo "Building App Bundle for Play Store..."
                sh "flutter build appbundle --release"
                
                // Rename AAB with version number
                sh """
                    cd build/app/outputs/bundle/release/
                    cp app-release.aab ${env.APP_NAME}-${env.NEW_VERSION}-${env.NEW_BUILD_NUMBER}.aab
                    ls -lh *.aab
                """
            }
        }
        
        stage('Publish to Play Store') {
            when {
                expression { params.PUBLISH_TO_PLAY_STORE == true }
            }
            steps {
                script {
                    // Use default track if parameter not set (when checkbox unchecked)
                    def track = params.PLAY_STORE_TRACK ?: 'internal'
                    def releaseStatus = params.PLAY_STORE_RELEASE_STATUS ?: 'draft'
                    echo "Publishing to Google Play Store (${track} track, ${releaseStatus} status)..."
                    
                    withCredentials([file(
                        credentialsId: env.PLAY_STORE_CREDENTIALS_ID,
                        variable: 'PLAY_STORE_CONFIG_JSON'
                    )]) {
                        // Create release notes directory
                        sh '''
                            mkdir -p android/app/src/main/play/release-notes/en-US
                        '''
                        
                        // Write release notes to file
                        def releaseNotesContent = params.RELEASE_NOTES?.trim() ?: "Version ${env.NEW_VERSION}\n\nBuild: ${env.NEW_BUILD_NUMBER}"
                        writeFile file: 'android/app/src/main/play/release-notes/en-US/default.txt', text: releaseNotesContent
                        
                        // Set environment variables for Gradle
                        def gradleEnv = "PLAY_STORE_TRACK=${track} PLAY_STORE_RELEASE_STATUS=${releaseStatus}"
                        
                        // Publish to Play Store using Gradle task
                        sh """
                            cd android
                            ${gradleEnv} ./gradlew publishBundle --no-daemon
                        """
                        
                        if (releaseStatus == 'draft') {
                            echo "✅ Uploaded to Play Store (${track} track, DRAFT status)"
                            echo "Visit https://play.google.com/console to review and publish the release"
                        } else if (track == 'production') {
                            echo "✅ Published to Play Store (PRODUCTION - public release, COMPLETED status)"
                            echo "Release will be available after Google's review (1-7 days)"
                        } else {
                            echo "✅ Published to Play Store (${track} track, COMPLETED status)"
                            echo "Visit https://play.google.com/console to promote to production"
                        }
                    }
                }
            }
        }
        
        stage('Commit Version Changes') {
            steps {
                script {
                    echo 'Committing version changes...'
                    sh """
                        git add pubspec.yaml
                        git commit -m "chore: bump version to ${env.NEW_VERSION}+${env.NEW_BUILD_NUMBER}" || echo "No changes to commit"
                    """
                }
            }
        }
        
        stage('Create Git Tag') {
            steps {
                script {
                    echo "Creating git tag ${env.VERSION_TAG}..."
                    sh """
                        git tag -a ${env.VERSION_TAG} -m "Release ${env.NEW_VERSION}"
                        git tag -l | tail -5
                    """
                }
            }
        }
        
        stage('Push to Forgejo') {
            steps {
                script {
                    echo 'Pushing changes and tags to Forgejo (mirrored to GitHub automatically)...'
                    withCredentials([string(
                        credentialsId: env.FORGEJO_CREDENTIALS_ID,
                        variable: 'FORGEJO_TOKEN'
                    )]) {
                        sh """
                            git push https://${FORGEJO_TOKEN}@${env.FORGEJO_HOST}/${env.FORGEJO_REPO}.git HEAD:${env.GIT_BRANCH_NAME}
                            git push https://${FORGEJO_TOKEN}@${env.FORGEJO_HOST}/${env.FORGEJO_REPO}.git ${env.VERSION_TAG}
                        """
                    }
                }
            }
        }
        
        stage('Create Forgejo Release') {
            steps {
                script {
                    echo "Creating Forgejo release ${env.VERSION_TAG}..."
                    
                    // Prepare release notes
                    def releaseBody = "Release ${env.NEW_VERSION}\n\n"
                    if (params.RELEASE_NOTES?.trim()) {
                        releaseBody += "## Release Notes\n${params.RELEASE_NOTES}\n\n"
                    }
                    releaseBody += "**Build:** ${env.NEW_BUILD_NUMBER}\n"
                    releaseBody += "**Release Type:** ${params.RELEASE_TYPE}\n\n"
                    releaseBody += "_Generated by Jenkins CI_"
                    
                    withCredentials([string(
                        credentialsId: env.FORGEJO_CREDENTIALS_ID,
                        variable: 'FORGEJO_TOKEN'
                    )]) {
                        // Write JSON payload to file to avoid escaping issues
                        def releasePayload = groovy.json.JsonOutput.toJson([
                            tag_name: env.VERSION_TAG,
                            name: "Release ${env.NEW_VERSION}",
                            body: releaseBody,
                            draft: false,
                            prerelease: false
                        ])
                        
                        writeFile file: 'release_payload.json', text: releasePayload
                        
                        // Create release using Forgejo API
                        sh '''
                            curl -sS -X POST \
                                -H "Authorization: token ${FORGEJO_TOKEN}" \
                                -H "Accept: application/json" \
                                -H "Content-Type: application/json" \
                                https://${FORGEJO_HOST}/api/v1/repos/${FORGEJO_REPO}/releases \
                                -d @release_payload.json > release_response.json
                            
                            cat release_response.json
                        '''
                        
                        // Extract release ID
                        def releaseId = sh(
                            script: "grep -o '\"id\":[0-9]*' release_response.json | head -1 | cut -d: -f2",
                            returnStdout: true
                        ).trim()
                        
                        if (!releaseId) {
                            error('Could not create Forgejo release (no release id in response)')
                        }
                        echo "Release ID: ${releaseId}"
                        
                        // Upload APK as release attachment
                        sh """
                            curl -sS -X POST \
                                -H "Authorization: token ${FORGEJO_TOKEN}" \
                                -F "attachment=@build/app/outputs/flutter-apk/${env.APP_NAME}-${env.NEW_VERSION}-${env.NEW_BUILD_NUMBER}.apk" \
                                "https://${env.FORGEJO_HOST}/api/v1/repos/${env.FORGEJO_REPO}/releases/${releaseId}/assets?name=${env.APP_NAME}-${env.NEW_VERSION}-${env.NEW_BUILD_NUMBER}.apk"
                        """
                        
                        echo "✅ Forgejo release created: https://${env.FORGEJO_HOST}/${env.FORGEJO_REPO}/releases/tag/${env.VERSION_TAG}"
                    }
                }
            }
        }
        
        stage('Archive Artifacts') {
            steps {
                echo 'Archiving APK in Jenkins...'
                script {
                    archiveArtifacts artifacts: "build/app/outputs/flutter-apk/${env.APP_NAME}-${env.NEW_VERSION}-${env.NEW_BUILD_NUMBER}.apk",
                                     fingerprint: true,
                                     allowEmptyArchive: false
                    
                    // Archive AAB if it was built
                    if (params.PUBLISH_TO_PLAY_STORE == true) {
                        archiveArtifacts artifacts: "build/app/outputs/bundle/release/${env.APP_NAME}-${env.NEW_VERSION}-${env.NEW_BUILD_NUMBER}.aab",
                                         fingerprint: true,
                                         allowEmptyArchive: false
                    }
                }
            }
        }
    }
    
    post {
        success {
            script {
                echo "✅ Build completed successfully!"
                echo "Version: ${env.NEW_VERSION}+${env.NEW_BUILD_NUMBER}"
                echo "Tag: ${env.VERSION_TAG}"
                echo "Forgejo Release: https://${env.FORGEJO_HOST}/${env.FORGEJO_REPO}/releases/tag/${env.VERSION_TAG}"
                
                if (params.PUBLISH_TO_PLAY_STORE == true) {
                    def track = params.PLAY_STORE_TRACK ?: 'internal'
                    def releaseStatus = params.PLAY_STORE_RELEASE_STATUS ?: 'draft'
                    echo "✅ Published to Play Store (${track} track, ${releaseStatus} status)"
                    echo "Play Console: https://play.google.com/console"
                }
            }
        }
        failure {
            echo '❌ Build failed!'
        }
        cleanup {
            script {
                // Only clean workspace if it exists
                try {
                    cleanWs()
                } catch (Exception e) {
                    echo "Workspace cleanup skipped: ${e.message}"
                }
            }
        }
    }
}
