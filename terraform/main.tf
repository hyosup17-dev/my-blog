
resource "aws_s3_bucket" "blog_bucket" {
    bucket = "my-hugo-blog-for-terraform-test" # 버킷 이름은 유일해야 한다.
}

resource "aws_s3_bucket_website_configuration" "blog_website" { # 버킷을 웹사이트로 설정
    bucket = aws_s3_bucket.blog_bucket.id

    index_document {
        suffix = "index.html" # 누군가 '/'(루트)로 접속하면 보여줄 기본 파일
    }

    error_document {
        key = "404.html" # 페이지를 찾을 수 없을 때(404) 보여줄 파일
    }
}

resource "aws_s3_bucket_policy" "blog_policy" { # S3 '웹사이트'는 기본적으로 '공개'되어야 작동.
    bucket = aws_s3_bucket.blog_bucket.id       # "누구나(Principal: "*") 이 버킷의 파일을 읽을(s3:GetObject) 수 있게 허용"하는 정책
    policy = jsonencode({
        Version = "2012-10-17",
        Statement = [{
            Sid       = "PublicReadGetObject",
            Effect    = "Allow",
            Principal = "*",
            Action    = "s3:GetObject",
            Resource  = "${aws_s3_bucket.blog_bucket.arn}/*"
        }]
    })

    depends_on = [
    aws_s3_bucket_public_access_block.blog_public_access
  ]
}

resource "aws_s3_bucket_public_access_block" "blog_public_access" { # 요즘 AWS는 기본적으로 모든 퍼블릭 접근을 차단하기 때문에
    bucket = aws_s3_bucket.blog_bucket.id                           # 3번에서 정책을 허용했더라도, 이 설정이 막고 있으면 소용이 없다.
                                                                    # 따라서 "퍼블릭 정책을 허용하겠다"라고 명시적으로 차단을 해제 해야함. 
    block_public_acls       = false
    block_public_policy     = false
    ignore_public_acls      = false
    restrict_public_buckets = false
}

resource "aws_cloudfront_distribution" "blog_cdn" { # S3 웹사이트를 전 세계로 빠르게 전달해줄 배달망(CDN)

    origin {
        domain_name = aws_s3_bucket_website_configuration.blog_website.website_endpoint
        origin_id   = "S3-Blog-Website-Origin"

        custom_origin_config {
            http_port               = 80
            https_port              = 443
            origin_protocol_policy = "http-only"
            origin_ssl_protocols   = ["TLSv1.2"]
        }
    }

    enabled             = true # 배포판 활성화
    is_ipv6_enabled     = true
    default_root_object = "index.html" # 도메인만 쳤을 때 보여줄 기본 파일

    default_cache_behavior {
        allowed_methods  = ["GET", "HEAD"] # 읽기만 허용
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = "S3-Blog-Website-Origin"

        viewer_protocol_policy = "redirect-to-https" # 사용자는 무조건 https로 접속하도록 강제 (보안 강화)
        compress               = true # 파일을 압축해서 전송 (속도 향상)

        # 캐시 시간 설정 (테스트 시 짧게, 운영 시 길게)
        min_ttl     = 0
        default_ttl =3600
        max_ttl     = 86400

        forwarded_values {
            query_string = false # 쿼리 스트링 (?id=1)을 S3로 전달하지 않음
            cookies {
                forward = "none" # 쿠키를 S3로 전달하지 않음
            }
        }
    }

    restrictions { # 접속 제한 설정 (모든 국가 허용)
        geo_restriction {
            restriction_type = "none"
        }
    }

    viewer_certificate { # SSL 인증서 설정
        cloudfront_default_certificate = true
    }

    depends_on = [ # 3,4번 리소스가 먼저 실행되어야 CloudFront가 오류 없이 생성됨
        aws_s3_bucket_policy.blog_policy,
        aws_s3_bucket_public_access_block.blog_public_access
    ]
}

