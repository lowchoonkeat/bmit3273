# Task 3: S3 Static Website (20%)
echo "[Task 3: S3 Static Website (20%)]" | tee -a grading_report.txt
bucket_name=$(aws s3api list-buckets --query "Buckets[].Name" --output text | tr '\t' '\n' | grep "^s3-$lowername" | head -n1)

if [ -z "$bucket_name" ]; then
  echo "❌ No S3 bucket found with prefix 's3-$lowername'" | tee -a grading_report.txt
else
  echo "✅ S3 bucket '$bucket_name' found" | tee -a grading_report.txt
  ((score+=4))  # Bucket created

  website_status=$(aws s3api get-bucket-website --bucket "$bucket_name" 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "✅ Static website hosting enabled for $bucket_name" | tee -a grading_report.txt
    ((score+=6))
  else
    echo "❌ Static website hosting not enabled for $bucket_name" | tee -a grading_report.txt
  fi

  s3_url="http://$bucket_name.s3-website-$region.amazonaws.com"
  if curl -s "$s3_url" | grep -iq "$fullname"; then
    echo "✅ S3 site displays student name" | tee -a grading_report.txt
    ((score+=10))
  else
    echo "❌ S3 site does not show student name or inaccessible" | tee -a grading_report.txt
  fi
fi
