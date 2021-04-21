import brownie
import time
import constants
import pytest


def test_batcher(dai, cdai, batcher, accounts):
    investors = accounts[1:]
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




