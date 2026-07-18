from pydantic_settings import BaseSettings


class MSKTokenProvider:
    """
    Provides short-lived IAM tokens for MSK authentication.
    Uses the pod's IRSA role automatically via boto3 credential chain.
    Token is refreshed before expiry by aiokafka.
    """
    def __init__(self, region: str):
        self.region = region

    def token(self) -> tuple[str, float]:
        from aws_msk_iam_sasl_signer import MSKAuthTokenProvider
        return MSKAuthTokenProvider.generate_auth_token(self.region)


class Settings(BaseSettings):
    kafka_bootstrap_servers: str = "localhost:9092"
    payments_topic: str = "payments"
    aws_region: str = "us-east-1"
    # Set to "SASL_SSL" for MSK, "PLAINTEXT" for local docker-compose
    kafka_security_protocol: str = "PLAINTEXT"
    port: int = 8000

    def get_msk_token_provider(self) -> MSKTokenProvider:
        return MSKTokenProvider(self.aws_region)

    class Config:
        env_file = ".env"


settings = Settings()
