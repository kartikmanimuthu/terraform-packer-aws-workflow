#!/bin/bash

# Log all output
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting user data script execution at $(date)"

# Update system
yum update -y

# Install required packages
yum install -y docker git awscli

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Install Node.js (version 18)
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# Verify installations
echo "Node.js version: $(node --version)"
echo "NPM version: $(npm --version)"
echo "Docker version: $(docker --version)"

# Create application directory
mkdir -p /opt/app
cd /opt/app

# Create a simple Node.js application
cat > package.json << 'EOF'
{
  "name": "${project_name}-app",
  "version": "1.0.0",
  "description": "Sample application for ${project_name}",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "morgan": "^1.10.0",
    "helmet": "^7.0.0",
    "cors": "^2.8.5"
  },
  "engines": {
    "node": ">=18.0.0",
    "npm": ">=8.0.0"
  }
}
EOF

# Create the main server file
cat > server.js << 'EOF'
const express = require('express');
const morgan = require('morgan');
const helmet = require('helmet');
const cors = require('cors');

const app = express();
const port = process.env.PORT || 3000;
const environment = process.env.NODE_ENV || '${environment}';

// Security middleware
app.use(helmet());
app.use(cors());

// Logging middleware
app.use(morgan('combined'));

// Parse JSON bodies
app.use(express.json());

// Health check endpoint (required for ALB health checks)
app.get('/health', (req, res) => {
    const healthStatus = {
        status: 'healthy',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        environment: environment,
        version: '1.0.0',
        build_tool: 'Terraform + Packer',
        instance_id: process.env.INSTANCE_ID || 'local',
        region: '${region}',
        project: '${project_name}',
        memory: {
            used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024),
            total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024)
        }
    };
    
    res.status(200).json(healthStatus);
});

// Root endpoint
app.get('/', (req, res) => {
    res.json({
        message: 'Sample Node.js Application - ${project_name}',
        timestamp: new Date().toISOString(),
        environment: environment,
        build_tool: 'Terraform + Packer',
        region: '${region}',
        endpoints: {
            health: '/health',
            info: '/info',
            metrics: '/metrics'
        }
    });
});

// Info endpoint with system information
app.get('/info', (req, res) => {
    const info = {
        application: '${project_name}',
        version: '1.0.0',
        environment: environment,
        build_tool: 'Terraform + Packer',
        region: '${region}',
        node_version: process.version,
        platform: process.platform,
        architecture: process.arch,
        uptime_seconds: Math.floor(process.uptime()),
        timestamp: new Date().toISOString()
    };
    
    res.json(info);
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
    const metrics = {
        timestamp: new Date().toISOString(),
        uptime_seconds: Math.floor(process.uptime()),
        memory_usage: {
            heap_used_mb: Math.round(process.memoryUsage().heapUsed / 1024 / 1024),
            heap_total_mb: Math.round(process.memoryUsage().heapTotal / 1024 / 1024),
            external_mb: Math.round(process.memoryUsage().external / 1024 / 1024),
            rss_mb: Math.round(process.memoryUsage().rss / 1024 / 1024)
        },
        cpu_usage: process.cpuUsage(),
        environment: environment,
        build_tool: 'Terraform + Packer'
    };
    
    res.json(metrics);
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('Error:', err.message);
    res.status(500).json({
        error: 'Internal Server Error',
        timestamp: new Date().toISOString()
    });
});

// 404 handler
app.use((req, res) => {
    res.status(404).json({
        error: 'Not Found',
        path: req.path,
        timestamp: new Date().toISOString()
    });
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('SIGTERM received, shutting down gracefully...');
    server.close(() => {
        console.log('Process terminated');
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    console.log('SIGINT received, shutting down gracefully...');
    server.close(() => {
        console.log('Process terminated');
        process.exit(0);
    });
});

const server = app.listen(port, '0.0.0.0', () => {
    console.log(`${project_name} application listening on port 3000`);
    console.log(`Environment: ${environment}`);
    console.log(`Region: ${region}`);
    console.log(`Health check: http://localhost:3000/health`);
});

module.exports = app;
EOF

# Set proper ownership
chown -R ec2-user:ec2-user /opt/app

# Install dependencies
echo "Installing Node.js dependencies..."
npm install

# Create systemd service for the application
cat > /etc/systemd/system/${project_name}-app.service << EOF
[Unit]
Description=${project_name} Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/app
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=${environment}
Environment=INSTANCE_ID=\$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the application service
systemctl daemon-reload
systemctl enable ${project_name}-app
systemctl start ${project_name}-app

# Wait a moment and check if the service started successfully
sleep 5
if systemctl is-active --quiet ${project_name}-app; then
    echo "Application service started successfully"
else
    echo "Application service failed to start"
    systemctl status ${project_name}-app
fi

# Install CloudWatch agent
echo "Installing CloudWatch agent..."
wget https://s3.${region}.amazonaws.com/amazoncloudwatch-agent-${region}/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/messages",
                        "log_group_name": "/aws/ec2/${project_name}/packer-app",
                        "log_stream_name": "{instance_id}/messages"
                    },
                    {
                        "file_path": "/var/log/user-data.log",
                        "log_group_name": "/aws/ec2/${project_name}/packer-app",
                        "log_stream_name": "{instance_id}/user-data"
                    },
                    {
                        "file_path": "/var/log/${project_name}-app.log",
                        "log_group_name": "/aws/ec2/${project_name}/packer-app",
                        "log_stream_name": "{instance_id}/application"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "${project_name}/EC2",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait", 
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch agent
echo "Starting CloudWatch agent..."
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

# Test the application
echo "Testing application endpoints..."
sleep 10
curl -f http://localhost:3000/health || echo "Health check failed"
curl -f http://localhost:3000/ || echo "Root endpoint failed"

# Log completion
echo "User data script completed successfully at $(date)"
