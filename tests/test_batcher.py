import brownie
import time
import constants
import pytest
from eth_account import Account
from eth_account._utils.structured_data.hashing import hash_domain
from eth_account.messages import encode_structured_data
from eth_utils import encode_hex


def test_dai_permit_deposit(dai_owned, cdai, batcher):
    dai = dai_owned
    signer = Account.create()
    holder = signer.address
    amount = constants.DEPOSIT_AMOUNT
    dai.transfer(holder, amount)
    assert dai.balanceOf(holder) == amount
    permit = build_permit(holder, str(batcher), dai, 3600)
    signed = signer.sign_message(permit)
    print(signed.v, signed.r, signed.s)
    batcher.permitAndDeposit(amount, 0, 0, signed.v, signed.r, signed.s, {"from": holder})
    print(dai.balanceOf(batcher.address))
    print(batcher.userBatchTotal(0, holder, {"from": holder}))


def test_dai_permit(dai_owned, batcher, accounts):
    dai = dai_owned
    signer = Account.create()
    holder = signer.address
    permit = build_permit(holder, str(batcher), dai, 3600)
    signed = signer.sign_message(permit)
    print(signed.v, signed.r, signed.s)
    dai.permit(holder, batcher, 0, 0, True, signed.v, signed.r, signed.s)
    assert dai.allowance(holder, batcher) == 2**256 - 1


def test_batcher_no_permit(dai, cdai, batcher, accounts):
    investors = accounts[1:10]
    for n, investor in enumerate(investors):
        dai.approve(batcher, constants.DEPOSIT_AMOUNT + n * 100e18, {"from": investor})
        batcher.deposit(constants.DEPOSIT_AMOUNT + n * 100e18, {"from": investor})
    batch_id = 0
    assert batcher.batchTotal(batch_id) == constants.DEPOSIT_AMOUNT * len(investors) + 3600e18
    batcher.depositToCompound({"from": accounts[0]})
    cdai_balance = cdai.balanceOf(batcher.address, {"from": accounts[0]})
    assert cdai_balance > 0
    assert dai.balanceOf(batcher.address, {"from": accounts[0]}) == 0
    assert cdai.balanceOf(accounts[0], {"from": accounts[0]}) > 0
    for investor in investors:
        print(cdai.balanceOf(batcher.address, {"from": accounts[0]}))
        tx = batcher.userWithdrawCTokens(batch_id, {"from": investor})
        print(tx.events["CTokenWithdrawn"]["amount"])
        assert cdai.balanceOf(investor, {"from": accounts[0]}) > 0
    assert round(cdai.balanceOf(batcher.address, {"from": accounts[0]}), -2) == 0


def build_permit(holder, spender, dai_owned, expiry):
    data = {
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "version", "type": "string"},
                {"name": "chainId", "type": "uint256"},
                {"name": "verifyingContract", "type": "address"},
            ],
            "Permit": [
                {"name": "holder", "type": "address"},
                {"name": "spender", "type": "address"},
                {"name": "nonce", "type": "uint256"},
                {"name": "expiry", "type": "uint256"},
                {"name": "allowed", "type": "bool"},
            ],
        },
        "domain": {
            "name": dai_owned.name(),
            "version": dai_owned.version(),
            "chainId": 1,
            "verifyingContract": str(dai_owned),
        },
        "primaryType": "Permit",
        "message": {
            "holder": holder,
            "spender": spender,
            "nonce": dai_owned.nonces(holder),
            "expiry": 0,
            "allowed": True,
        },
    }
    assert encode_hex(hash_domain(data)) == dai_owned.DOMAIN_SEPARATOR()
    return encode_structured_data(data)
