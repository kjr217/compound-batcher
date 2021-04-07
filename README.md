# compound-batcher

For tests:
 
1. Add Infura Id to environmental variables. https://eth-brownie.readthedocs.io/en/stable/network-management.html#using-infura 

2. Add ETHERSCAN_TOKEN to environmental variables.

3. Run below:

```
$ cd solidity
$ brownie test tests/mainnet-fork-tests --network mainnet-fork -s
```
