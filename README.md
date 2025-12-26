# 🔧 Smart DNS & SNI Proxy for Access to Google Gemini and Other Services

## 📜 Detailed Project History

This project was born not from a textbook, but from the practical need to access services like **Google Gemini (Gemini Advanced)** in a region where they are blocked. This is a story about how standard bypass methods proved useless against modern DPI (Deep Packet Inspection), and how a working, albeit non-trivial, system was built.

### The Problem
Simple VPNs and Shadowsocks were easily detected and blocked. Proxying through a regular web proxy didn't work because Google clients (browser, API) use **strict TLS and SNI (Server Name Indication) verification**. Blocking occurred precisely at the stage of analyzing SNI in the TLS handshake.

### The Solution
A two-component system was implemented:
1.  **Local Smart DNS Server (AdGuard Home)**: Intercepts requests to blocked domains and "tricks" the client by providing the IP address of our proxy server.
2.  **Transparent SNI Proxy on Nginx**: Accepts encrypted TLS traffic, reads the server name (SNI) from it without decrypting the content, and redirects the connection to the real Google server. To an external observer, this looks like a legitimate connection to our server.

**Traffic Flow Diagram:**
[Your Computer] --DNS--> [AdGuard Home] --DNS response with proxy IP--> [Your Computer]
[Your Computer] --HTTPS traffic--> [SNI Proxy on Nginx] --Redirection via SNI--> [Google Servers]

text

## 🚀 Features and Advantages

*   **Bypasses Modern Blocking**: The system effectively works against DPI and SNI-filtering based blocks.
*   **Low Latency**: Main traffic goes through your proxy server located abroad. Placing AdGuard Home locally only speeds up the DNS request stage.
*   **Additional Benefits**: AdGuard Home provides network-level ad and tracker blocking for all devices.
*   **Automation**: Scripts to maintain up-to-date Google IPs and prepare the project for deployment.

## 📂 Project Structure
smart-dns-sni-proxy/
├── docker-compose.yml # Main file to run all services
├── nginx-sni.conf # SNI proxy configuration (main component)
├── nginx-dot.conf # DNS-over-TLS proxy configuration (optional)
├── scripts/
│ ├── update-google-ip.sh # Script for automatic Google IP updates in config
│ └── prepare-for-github.sh # Script to "clean" the project before publication
├── config-examples/
│ └── AdGuardHome.yaml.example # AdGuard Home config template WITHOUT passwords & keys
├── .env.example # Example environment variables file
├── .gitignore # Git file excluding secret data
├── README.md # This file (in Russian)
├── README_EN.md # This file (in English)
└── setup.sh # Quick deployment script (optional)

text

## ⚙️ Detailed Installation Guide

### Prerequisites
*   A server outside the blocking zone with Docker and Docker Compose installed.
*   A white (public) IP address on this server.
*   Basic Linux command line skills.

### Step 1: Cloning and Configuration
```bash
# 1. Clone the repository
git clone <your-repository-url>
cd smart-dns-sni-proxy

# 2. Create and configure the secrets file based on the example
cp .env.example .env
nano .env # Edit, specifying your SERVER_IP and other data

# 3. Create working directories and the AdGuard config
mkdir -p adguard-data/conf
cp config-examples/AdGuardHome.yaml.example adguard-data/conf/AdGuardHome.yaml

# 4. OPEN AND THOROUGHLY EDIT this file:
nano adguard-data/conf/AdGuardHome.yaml
Key Settings in AdGuardHome.yaml
User and Password: Replace YOUR_USERNAME and YOUR_PASSWORD_HASH. You can generate the hash with:

bash
docker run --rm adguard/adguardhome:v0.107.49 hash-password -p 'your_strong_password'
DNS Rewrites: Ensure that in the filtering -> rewrites section for all Google domains (*.google.com, *.googleapis.com, etc.), the answer field contains your server's IP address (the same as in .env).

TLS Certificates: If you plan to use DNS-over-TLS, insert your certificate_chain and private_key.

Step 2: Launching the System
bash
# Run all containers in the background
docker compose up -d

# Check status
docker compose ps

# View logs if something goes wrong
docker compose logs -f sni-proxy
Step 3: Client Configuration
DNS: On the device needing access, specify in the network settings the DNS server — your server's IP address.

Testing: Open a browser and try to visit gemini.google.com. Traffic should now flow through your system.

🛠️ Technical Details and Troubleshooting
How the SNI Proxy Works (nginx-sni.conf)
Nginx in stream mode with the ssl_preread on option enabled can peek into the beginning of the TLS handshake and extract the server name without decrypting the entire session. Based on this name (via the map directive), it decides where to redirect the TCP connection.

Important Nuances Learned in Practice
Don't Mix TLS Termination and SNI Proxy: The initial attempt to use Caddy to accept HTTPS and proxy to Nginx created an extra TLS layer. The final solution — the SNI proxy (sni-proxy) must listen on port 443 directly.

AdGuard Must Return the Proxy IP, Not the Final Server IP: A classic mistake is to configure AdGuard to return Google's IP. This breaks the entire chain because the client will try to connect directly to the blocked IP.

Automatic Google IP Updates: Google's IP addresses change over time. The scripts/update-google-ip.sh script, run via cron, solves this problem.

Common Problems and Solutions
Problem	Possible Cause	Solution
Google sites don't open	AdGuard returns the wrong IP	Check the rewrites section in AdGuardHome.yaml.
Server firewall	Open ports 53 (UDP/TCP for DNS) and 443 (TCP for HTTPS).
Old Caddy container running	Stop it: docker stop caddy-https; docker rm caddy-https.
Error port is already allocated	Port 443 is busy by another process	Find and free the port or use docker compose up -d --remove-orphans.
No logs in sni-proxy	Requests aren't reaching port 443	Check DNS settings on the client and rewrites in AdGuard.
Very slow performance	High ping to the server	Consider renting a VPS in a country with better ping (Kazakhstan, Turkey).
System Health Check
bash
# 1. Check DNS (should return your server's IP)
nslookup google.com <YOUR_SERVER_IP>

# 2. Check SNI proxy (key flags: --resolve and -k)
curl -vk --resolve "google.com:443:<YOUR_SERVER_IP>" https://google.com

# 3. View SNI proxy logs in real time
docker compose logs -f --tail=10 sni-proxy
🔄 Maintenance
Automatic Google IP Updates
Configure cron to run the script daily:

bash
# Open crontab
crontab -e
# Add line (update at 3:00 AM daily)
0 3 * * * cd /path/to/project && ./scripts/update-google-ip.sh >> ./logs/cron.log 2>&1
Certificate Updates
If you use DNS-over-TLS with your own certificates, remember to renew them before expiration. Place new files in the nginx-certs/ directory and restart the dot-proxy service.

📝 License and Disclaimer
This project is distributed under the MIT License.

IMPORTANT: The use of technologies to bypass network restrictions may be regulated by local laws. This project is presented for educational and research purposes. The author is not responsible for how this code is applied.

P.S. This README is not just an instruction, but a summary of many hours of searching, trial, and error. I hope it saves your time and helps you avoid the same "rakes" we stepped on. Good luck!
