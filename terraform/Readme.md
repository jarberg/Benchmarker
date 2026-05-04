
# build the docker image
docker compose build


# start docker image 
docker compose up localstack -d

# run this for new clones and restart entire pipeline
docker compose run --rm terraform init

# detect cahnges and make a plan for update and make plan file
docker compose run --rm terraform plan -out=tfplan

# apply the plan made from the plan file
docker compose run --rm terraform apply tfplan

# destroy the current state
docker compose run --rm terraform destroy







# List every resource Terraform is tracking
docker compose run --rm terraform state list

# Drill into any specific resource
docker compose run --rm terraform state show module.vpc.aws_vpc.this[0]