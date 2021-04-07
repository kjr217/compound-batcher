import brownie
import time
import constants
import pytest


def test_batcher(dai, cdai, batcher, accounts):
    investors = accounts[1:]
    for investor in investors:
        dai.approve(batcher, constants.DEPOSIT_AMOUNT, {"from": investor})
        batcher.userDeposit(constants.DEPOSIT_AMOUNT, {"from": investor})

    assert batcher.toDeposit() == constants.DEPOSIT_AMOUNT * len(investors)
    batcher.depositToCompound({"from": accounts[0]})
    cdai_balance = cdai.balanceOf(batcher.address, {"from": accounts[0]})
    print(cdai_balance)
    assert cdai_balance > 0
    assert dai.balanceOf(batcher.address, {"from": accounts[0]}) == 0

    for investor in investors:
        batcher.userWithdrawCTokens({"from": investor})
        assert cdai.balanceOf(investor, {"from": accounts[0]}) > 0
    assert round(cdai.balanceOf(batcher.address, {"from": accounts[0]}), -2) == 0
    for investor in investors:
        dai.approve(batcher, constants.DEPOSIT_AMOUNT, {"from": investor})
        batcher.userDeposit(constants.DEPOSIT_AMOUNT, {"from": investor})
    batcher.depositToCompound({"from": accounts[0]})
    new_cdai_balance = cdai.balanceOf(batcher.address, {"from": accounts[0]})
    print(new_cdai_balance)

    for investor in investors:
        dai.approve(batcher, constants.DEPOSIT_AMOUNT, {"from": investor})
        batcher.userDeposit(constants.DEPOSIT_AMOUNT, {"from": investor})

    batcher.depositToCompound({"from": accounts[0]})
    newer_cdai_balance = cdai.balanceOf(batcher.address, {"from": accounts[0]})
    assert newer_cdai_balance > new_cdai_balance
    print(newer_cdai_balance)
    total_bals = 0
    for investor in investors:
        tx = batcher.userWithdrawCTokens({"from": investor})
        assert cdai.balanceOf(investor, {"from": accounts[0]}) > 0
        total_bals += cdai.balanceOf(investor, {"from": accounts[0]})
    assert total_bals == pytest.approx(cdai_balance + newer_cdai_balance)
    print(total_bals, cdai_balance + newer_cdai_balance)
    assert round(cdai.balanceOf(batcher.address, {"from": accounts[0]}), -2) == 0
    print(cdai.balanceOf(batcher.address, {"from": accounts[0]}))



