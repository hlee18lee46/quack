🚀 How to Run
1. Backend Setup (Python)
The backend manages the connection between the mobile app, Snowflake, and the Solana blockchain.

Clone the repository:

Bash
git clone https://github.com/hlee18lee46/mediQuack.git
cd mediQuack

Set up Virtual Environment:

Bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
Snowflake Authentication:

Create a folder named keys in the root directory.

Generate your RSA keys for Snowflake:

Bash
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out keys/snowflake_key.pem -nocrypt
openssl rsa -in keys/snowflake_key.pem -pubout -out keys/snowflake_key.pub
Ensure your .env file points to keys/snowflake_key.pem.

Run the Server:

Bash
python app.py

2. Networking (ngrok)
Because the iOS app runs on a physical device, it needs a public URL to communicate with your local machine.

Start ngrok:

Bash
ngrok http 8000
Update Frontend: Copy the https URL provided by ngrok and paste it into the backendBaseURL variable in the iOS GraphView.swift file.

3. Frontend Setup (iOS)
Note: A physical iPhone is required to use the camera for vitals sensing; the Xcode Simulator will not work.

Open the ios/mediQuack.xcodeproj (or .xcworkspace) in Xcode.

Connect your iPhone via USB.

Select your iPhone as the target device.

Ensure your Signing & Capabilities are set with a valid developer team.

Click Run (Cmd + R) to install the app on your phone.


Meditation songs from below website, it's copyright free music

https://pixabay.com/music/search/meditation/