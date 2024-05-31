## Issues:

### 1. High - The stake function in Streets.sol does not have any access control

#### Technical Details

A malicious user can brute force the `stake()`function and pass any random id.
This gives an attacker the ability to use more NFTs than is alloted to him.

#### Impact

High. Users can not stake thier NFTs into the Street contract, causing grief to the users, denying them the opportunity to stake their NFTs

#### Recommendation

Use this check in the beginning of the `stake()` function.
This check verifies that the caller is the owner of the tokenId

```solidity
require(oneShotContract.ownerOf(tokenId) == msg.sender, "Caller is not the owner");
```

### 2. High - The random value calculation in the `_battle()` function in the RapBattle.sol contract can be exploited.

#### Technical Details

This is because the sources of randomness (block timestamp, block.prevrandao, and msg.sender) are predictable to a certain extent.

#### Impact

High. Miners and users can manipulate these values to influence the outcome of the random number generation. Hence the winner of the RapBattle many not always be randomly chosen

#### Recommendation

Use a verifiable random function like Chainlink VRF, which provides a secure and verifiable source of randomness.
