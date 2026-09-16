cat << 'EOF' > setup_lab.sh
#!/bin/bash
set -e

# Automatically fetch environment defaults
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
DEFAULT_ZONE=$(gcloud config get-value compute/zone 2>/dev/null || echo "us-central1-a")
DEFAULT_REGION=$(echo $DEFAULT_ZONE | cut -d'-' -f1,2)

echo "=========================================="
echo "    GCP LAB AUTOMATION SCRIPT WITH PROMPTS "
echo "=========================================="
echo "Detected Project ID: $PROJECT_ID"
echo "Detected Zone:       $DEFAULT_ZONE"
echo "Detected Region:     $DEFAULT_REGION"
echo "------------------------------------------"

# Prompt 1: Cloud SQL Instance Name
read -p "Enter Cloud SQL Instance ID [default: my-demo]: " INSTANCE_NAME
INSTANCE_NAME=${INSTANCE_NAME:-my-demo}

# Prompt 2: Cloud SQL Root Password
read -sp "Enter Root Password for MySQL [default: ChangeMe1!]: " DB_PASSWORD
echo ""
DB_PASSWORD=${DB_PASSWORD:-ChangeMe1!}

echo "------------------------------------------"
echo "Configuration Summary:"
echo " - Project ID:     $PROJECT_ID"
echo " - Instance Name:  $INSTANCE_NAME"
echo " - Password Set:   Yes"
echo "------------------------------------------"
read -p "Press [ENTER] to start execution..." unused_var

# Step 1: Export BigQuery Data
echo "==> [1/5] Exporting BigQuery data to CSV..."
bq query --use_legacy_sql=false --format=csv "SELECT start_station_name, COUNT(*) AS num FROM \`bigquery-public-data.london_bicycles.cycle_hire\` GROUP BY start_station_name ORDER BY num DESC;" > start_station_data.csv
bq query --use_legacy_sql=false --format=csv "SELECT end_station_name, COUNT(*) AS num FROM \`bigquery-public-data.london_bicycles.cycle_hire\` GROUP BY end_station_name ORDER BY num DESC;" > end_station_data.csv

# Step 2: Create Storage Bucket & Upload Files
echo "==> [2/5] Creating Cloud Storage Bucket and uploading files..."
gcloud storage buckets create gs://$PROJECT_ID --location=$DEFAULT_REGION || true
gcloud storage cp start_station_data.csv gs://$PROJECT_ID/
gcloud storage cp end_station_data.csv gs://$PROJECT_ID/

# Step 3: Create Cloud SQL Instance
echo "==> [3/5] Creating Cloud SQL Instance '$INSTANCE_NAME' (this may take a few minutes)..."
gcloud sql instances create $INSTANCE_NAME \
    --database-version=MYSQL_8_0 \
    --tier=db-custom-4-16384 \
    --root-password="$DB_PASSWORD" \
    --zone=$DEFAULT_ZONE \
    --quiet

# Step 4: Create Database & Import Tables
echo "==> [4/5] Setting up 'bike' database and importing CSV tables..."
gcloud sql databases create bike --instance=$INSTANCE_NAME

gcloud sql import csv $INSTANCE_NAME gs://$PROJECT_ID/start_station_data.csv --database=bike --table=london1 --quiet || true
gcloud sql import csv $INSTANCE_NAME gs://$PROJECT_ID/end_station_data.csv --database=bike --table=london2 --quiet || true

# Step 5: Final SQL Operations
echo "==> [5/5] Executing cleanup queries..."
gcloud sql db query bike --instance=$INSTANCE_NAME --use-main-password --quiet -e '
DELETE FROM london1 WHERE num=0;
DELETE FROM london2 WHERE num=0;
INSERT INTO london1 (start_station_name, num) VALUES ("test destination", 1);
SELECT start_station_name AS top_stations, num FROM london1 WHERE num>100000
UNION
SELECT end_station_name, num FROM london2 WHERE num>100000
ORDER BY top_stations DESC;
' <<< "$DB_PASSWORD"

echo "=========================================="
echo "    LAB SETUP COMPLETED SUCCESSFULLY!     "
echo "=========================================="
EOF

chmod +x setup_lab.sh
./setup_lab.sh
