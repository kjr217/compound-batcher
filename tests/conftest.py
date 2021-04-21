import pytest
import constants
import time
import brownie
from brownie import Contract
from brownie import (
    CompoundBatcherV2
)

@pytest.fixture(scope="function", autouse=True)
def isolate_func(fn_isolation):
    # perform a chain rewind after completing each test, to ensure proper isolation
    # https://eth-brownie.readthedocs.io/en/v1.10.3/tests-pytest-intro.html#isolation-fixtures
    pass


@pytest.fixture(scope="module", autouse=True)
def dai():
    yield Contract.from_explorer("0x6B175474E89094C44Da98b954EedeAC495271d0F")


@pytest.fixture(scope="module")
def cdai():
    yield Contract.from_explorer("0x5d3a536e4d6dbd6114cc1ead35777bab948e3643")


@pytest.fixture(scope="module", autouse=True)
def uniswap_dai_exchange():
    yield Contract.from_explorer("0x2a1530C4C41db0B0b2bB646CB5Eb1A67b7158667")


@pytest.fixture(scope="function", autouse=True)
def send_10_eth_of_dai_to_accounts(accounts, dai, uniswap_dai_exchange):
    for account in accounts[:10]:
        uniswap_dai_exchange.ethToTokenSwapInput(
            1,  # minimum amount of tokens to purchase
            10000000000,  # timestamp
            {"from": account, "value": "10 ether"},
        )
    yield dai


@pytest.fixture(scope="function", autouse=True)
def batcher(dai, accounts, cdai):
    batcher = CompoundBatcherV2.deploy({"from": accounts[0]})
    batcher.init(cdai.address, dai.address, {"from": accounts[0]})
    yield batcher