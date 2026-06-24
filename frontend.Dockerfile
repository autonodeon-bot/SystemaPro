# Multi-stage build for frontend
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY package.json ./
COPY package-lock.json* ./

# Install dependencies (ci надёжнее install на VPS)
RUN npm ci --no-audit --fund=false || (npm cache clean --force && npm ci --no-audit --fund=false)

# Copy source files
COPY . .

# Пустой VITE_API_BASE = запросы на тот же хост (/api проксируется nginx на backend)
ARG VITE_API_BASE=
ENV VITE_API_BASE=$VITE_API_BASE

# Меняйте при каждом деплое (docker-compose build --build-arg), чтобы сбрасывать кэш слоя сборки
ARG BUILD_REF=dev
RUN echo "frontend build ref: ${BUILD_REF}"

# Build the application
RUN ./node_modules/.bin/vite build

# Production stage
FROM nginx:alpine

# Copy built files from builder
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

# Expose ports 80 and 443
EXPOSE 80 443

# Start nginx
CMD ["nginx", "-g", "daemon off;"]



