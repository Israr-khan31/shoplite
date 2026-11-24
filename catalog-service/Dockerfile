
# Stage 1: Use Node.js
FROM node:22-alpine

# Create working directory
WORKDIR /app

# Copy dependency files
COPY package*.json ./

# Install production dependencies
RUN npm ci --omit=dev

# Copy application code
COPY src/ ./src/

# Application port
EXPOSE 3000

# Start catalog service
CMD ["npm", "start"]
