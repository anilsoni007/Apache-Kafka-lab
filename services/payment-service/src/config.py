from pydantic_settings import BaseSettings
from aiokafka.abc import AbstractTokenProvider


class MSKTokenProvider(AbstractTokenProvider):
    def __init__(self, region: str):
        self.region = region

    async def token(self) -> str:
        from aws_msk_iam_sasl_signer import MSKAuthTokenProvider
        t, _ = MSKAuthTokenProvider.generate_auth_token(self.region)
        return t


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
