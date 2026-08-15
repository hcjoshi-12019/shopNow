# ShopNow + Infra Project Summary

## Overview

This project demonstrates a complete cloud-native application deployment setup built around a full-stack e-commerce application called ShopNow.

The solution is divided into two cooperating repositories:

- `shopNow/` - application services and app-side CI/CD automation
- `herovired-infra/` - infrastructure, deployment, cluster, and automation layer

Together, they represent a real-world DevOps and Kubernetes workflow where application code is built into Docker images, pushed to Amazon ECR, and deployed to Amazon EKS.

---

## Application Layer

The application layer contains the actual product experience:

### Frontend

- React-based customer-facing web app
- serves the shopping experience for end users
- communicates with the backend API for product and order data

### Admin

- React-based admin dashboard
- used to manage application content and operations
- relies on the same backend services for control and data access

### Backend

- Node.js + Express service
- provides API routes for products, users, orders, and health checks
- connects to MongoDB for persistent data
- supports local development and deployment-ready structure

### Database

- MongoDB stores the application data
- backend connects using environment configuration and secret-driven setup in Kubernetes

---

## Infrastructure Layer

The infrastructure layer handles all runtime support for the application:

### Kubernetes

- manages deployment of frontend, admin, backend, and database components
- provides services, ingress, and namespace isolation
- enables traffic routing to the correct workloads

### Terraform

- provisions AWS foundation resources and cluster-related infrastructure
- supports reusable cloud setup and environment configuration

### Ansible

- configures management hosts and environment settings
- helps maintain consistent infrastructure automation

### Jenkins

- app pipeline builds and pushes Docker images to ECR
- infra pipeline applies cluster and deployment changes
- creates a structured CI/CD workflow across both repos

### AWS ECR and EKS

- ECR stores the application Docker images
- EKS runs the deployments and exposes the application in the cloud environment

---

## Deployment Flow

The end-to-end deployment model is:

1. Developer updates the app code.
2. The app pipeline detects changed services.
3. Docker images are built for the affected service(s).
4. Images are pushed to Amazon ECR.
5. The infra pipeline applies the latest deployment manifests.
6. EKS pulls the image and rolls out the new pods.
7. The application becomes available through Kubernetes services and ingress.
8. Developers validate app health, logs, endpoints, and functionality.

---

## Why the Two Services Are Dependent

The two repos are separate but tightly connected:

### shopNow depends on infra for:

- EKS cluster access
- Kubernetes manifests and deployment conventions
- AWS/ECR access and secret setup
- namespace and networking configuration
- CI/CD environment defaults

### Infra depends on shopNow for:

- the built Docker images
- app-level deployment metadata
- service deployment targets
- runtime image tags and app-specific config

In short:

- `shopNow` contains the application logic and delivery artifacts
- `herovired-infra` contains the platform and orchestration that runs the app

---

## Real-Time Runtime Behavior

When the application is running in production-like mode:

- users open the frontend in a browser
- the frontend makes requests to the backend API
- the backend reads and writes application data from MongoDB
- Kubernetes keeps the pods running and networked
- ingress exposes the services externally
- ECR stores the image versions used by the cluster

This is a real-world microservice-style deployment pattern built around cloud-native DevOps practices.

---

## Key Benefits of the Project

- application and infrastructure are separated by responsibility
- deployment is automated through Jenkins
- Docker image versioning is managed through ECR
- Kubernetes enables scalable runtime orchestration
- project demonstrates CI/CD, containerization, and cloud deployment in one setup

---

## Final Outcome

This project showcases how a real application can be:

- developed in a modular service structure
- containerized into Docker images
- stored in a cloud registry
- deployed to a managed Kubernetes cluster
- monitored and rolled out using pipeline-driven workflows

It is a complete example of a modern deployment pipeline for a full-stack application.
