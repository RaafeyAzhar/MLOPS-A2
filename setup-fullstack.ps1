# -----------------------------------------
# STEP 1: CREATE FOLDER STRUCTURE
# -----------------------------------------
New-Item -ItemType Directory -Path fullstack-app/frontend -Force
New-Item -ItemType Directory -Path fullstack-app/auth-service -Force
New-Item -ItemType Directory -Path fullstack-app/k8s -Force

# -----------------------------------------
# STEP 2: SETUP AUTH SERVICE
# -----------------------------------------
Set-Location fullstack-app/auth-service
npm init -y
npm install express mongoose bcryptjs jsonwebtoken cors dotenv

@"
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const dotenv = require('dotenv');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');

const app = express();
dotenv.config();
app.use(cors());
app.use(express.json());

mongoose.connect(process.env.MONGO_URI, { useNewUrlParser: true, useUnifiedTopology: true })
.then(() => console.log('MongoDB connected'))
.catch(err => console.error(err));

const userSchema = new mongoose.Schema({
  email: String,
  password: String
});
const User = mongoose.model('User', userSchema);

app.post('/signup', async (req, res) => {
  const { email, password } = req.body;
  const hashed = await bcrypt.hash(password, 10);
  const user = new User({ email, password: hashed });
  await user.save();
  res.status(201).send('User created');
});

app.post('/login', async (req, res) => {
  const { email, password } = req.body;
  const user = await User.findOne({ email });
  if (!user) return res.status(400).send('Invalid');
  const isMatch = await bcrypt.compare(password, user.password);
  if (!isMatch) return res.status(400).send('Invalid');
  const token = jwt.sign({ id: user._id }, process.env.JWT_SECRET);
  res.json({ token });
});

app.post('/forgot-password', async (req, res) => {
  res.send('Dummy forgot password endpoint');
});

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => console.log(`Auth service running on port \${PORT}`));
"@ | Set-Content -Path "server.js"

@"
MONGO_URI=mongodb://mongo:27017/authdb
JWT_SECRET=supersecretjwt
PORT=5000
"@ | Set-Content -Path ".env"

@"
FROM node:18
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 5000
CMD ["node", "server.js"]
"@ | Set-Content -Path "Dockerfile"

Set-Location ../..

# -----------------------------------------
# STEP 3: SETUP FRONTEND
# -----------------------------------------
Set-Location fullstack-app/frontend
npx create-vite@latest . -- --template react
npm install
npm install axios react-router-dom

@"
FROM node:18
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build
RUN npm install -g serve
CMD ["serve", "-s", "dist"]
"@ | Set-Content -Path "Dockerfile"

Set-Location ../..

# -----------------------------------------
# STEP 4: SETUP docker-compose.yml
# -----------------------------------------
@"
version: '3.8'
services:
  mongo:
    image: mongo
    container_name: mongo
    ports:
      - '27017:27017'

  auth:
    build: ./auth-service
    ports:
      - '5000:5000'
    depends_on:
      - mongo
    environment:
      - MONGO_URI=mongodb://mongo:27017/authdb
      - JWT_SECRET=supersecretjwt

  frontend:
    build: ./frontend
    ports:
      - '3000:3000'
    depends_on:
      - auth
"@ | Set-Content -Path "fullstack-app/docker-compose.yml"

# -----------------------------------------
# STEP 5: START LOCAL TEST
# -----------------------------------------
docker-compose -f fullstack-app/docker-compose.yml up --build

# -----------------------------------------
# STEP 6: PREPARE K8s YAML FILES
# -----------------------------------------
Set-Location fullstack-app/k8s

@"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongo-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mongo
  template:
    metadata:
      labels:
        app: mongo
    spec:
      containers:
      - name: mongo
        image: mongo
        ports:
        - containerPort: 27017
---
apiVersion: v1
kind: Service
metadata:
  name: mongo-service
spec:
  selector:
    app: mongo
  ports:
    - port: 27017
      targetPort: 27017
"@ | Set-Content -Path "mongo-deployment.yml"

@"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: auth
  template:
    metadata:
      labels:
        app: auth
    spec:
      containers:
      - name: auth
        image: auth-service
        ports:
        - containerPort: 5000
        env:
        - name: MONGO_URI
          value: mongodb://mongo-service:27017/authdb
        - name: JWT_SECRET
          value: supersecretjwt
---
apiVersion: v1
kind: Service
metadata:
  name: auth-service
spec:
  selector:
    app: auth
  ports:
    - port: 5000
      targetPort: 5000
"@ | Set-Content -Path "auth-deployment.yml"

@"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: frontend
        ports:
        - containerPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  type: NodePort
  selector:
    app: frontend
  ports:
    - port: 3000
      targetPort: 3000
      nodePort: 30080
"@ | Set-Content -Path "frontend-deployment.yml"

Set-Location ../..

# -----------------------------------------
# STEP 7: DEPLOY TO MINIKUBE
# -----------------------------------------
minikube start
& minikube docker-env | Invoke-Expression
docker build -t auth-service ./fullstack-app/auth-service
docker build -t frontend ./fullstack-app/frontend
kubectl apply -f fullstack-app/k8s

# -----------------------------------------
# STEP 8: ACCESS FRONTEND
# -----------------------------------------
minikube service frontend-service
