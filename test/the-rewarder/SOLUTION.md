## SOLUTION

An address which has a reward to claim in some ```Distribution```  needs to create a call to ```claimRewards()``` function with ```Claimed``` structs with the same ```tokenIndex``` stacked together inside of the ```inputClaims``` array

Since the reward is determined in the merkle tree and its root for users address, **user can only steal multiples** of his reward, though **amount of those multiples is unlimited**

To create an attack, calculate the amount of claims for each token ```Distribution``` as```uint256 claimsAmount == distributor.getRemaining(address(token)) / userReward```, ```userReward``` being the reward of that address. Rounding down of the division operation ensures that during the ```for``` cycle in ```claimRewards()``` the ```remaining``` amount will not underflow

```inputTokens``` array should just have all of the ```IERC20 token``` variables, to which ```Claim``` structures are pointing to. The order of them is not relevant

## FINDINGS

1. ```claimRewards()```  allows for **claiming rewards multiple times** with the same ```Claim```

```claimRewards()``` function goes through ```inputClaims``` array of ```Claim``` structures to verify the proof each structure has, accumulates the amounts claimed for each token and **sets those claims as used**

The problem lies in the way this function records claims that are used to protect from replaying the same claim

For this, ```_setClaimed()``` function is used. It checks whether the bit in the bitmap at coordinations provided as arguments ot the function is set or not. If it's not - it sets the bit and decreases the ```remaining``` amount in the ```Distribution``` stucture that ```IERC20 token``` points to. Note that this function **does not check** whether the ```amount``` is the amount of tokens the user is allowed to claim

But the vulnerability itself is **when those claims are recorded**. During the flow of the ```for``` cycle, ```claimRewards()``` **does not record each claim after it is verified and the tokens are sent**

```_setClaimed()``` is **only called when** under following conditions for some index ```i```:
   1. ```inputClaims[i].tokenIndex``` point to a new ```IERC20``` inside ```inputTokens``` array and it is not ``address(0)```
    On the first run of the cycle, local function variable ```IERC20 token``` is set to some token, meaning that any other token in ```inputClaims``` at any ```i``` will trigger ```_setClaimed()```
   2. ```i``` is the last run of the cycle
    Such index will inevitably trigger ```_setClaimed()``` call and set accumulated bits

This branch structure allows an attacker to create such ```inputClaims``` and ```inputTokens``` arrays, that **the same ```Claim``` struct can be used to steal almost all the tokens** in the ```Distribution```

The same ```Claim``` therefore means that **the same leaf of the merkle tree can be used multiple times**, unless it is set as claimed

To create an attack, a user would create such arguments to the ```claimRewards()``` call, such that the ```Claim``` structures with the same ```tokenIndex``` are stacked together. This will avoid triggering the first condition listed before 




