## SOLUTION

The following list is the way an attack that would steal all DVT from ```SelfiePool``` can be carried out:

1. Create an ```IERC3156FlashBorrower``` contract, that does the following inside the ```onFlashLoan()``` function in the same order:
   - Delegate borrowed tokes to itself
   - Queue the call to ```SelfiePool``` with ```emergencyExit()``` selector, encoded with ```recovery``` address
   - Approve the ```SimpleGovernance``` contract for the borrowed amount
2. Call ```flashLoan()```, borrowing the maximal amount and providing the created contract as ```receiver``` argument
3. Wait out the action delay - 2 days
4. Call ```executeAction()``` to steal DVT from ```SelfiePool```
## FINDINGS

1. ```SimpleGovernance``` allows for malicious actions to pass

The logic implemented in this contract **does not support voting on proposed actions, nor really proposing those actions**. The voting power is mapped 1:1 to the voting token. Contract **allows to que any action** without the community voting on it

The **only condition** someone has to meet in order **to queue any action** is defined in ```_hasEnoughVotes()``` function. An address needs to have their amount of voting power to be greater than the half of token's total supply, e.g. ```balance > halfTotalSupply```, with ```balance``` being the amount of votes the user has at the moment of queuing an action

2. Anyone can **steal all DVT** from ```SelfiePool```

```SelfiePool``` contract has one asset, users can take flash loans up to the full balance of ```SelfiePool```, since ```flashLoan()``` function **does not restrict** the ```amount``` argument passed to it

The total supply of the DVT token at deployment is set to **2 million tokens**. At the same, ```SelfiePool``` offers as much as **1.5 million tokens** in flash loans for free - this is a **critical vulnerability**, which allows anyone to use ```emergencyExit()``` function

A user can take a flash loan, and during its execution use borrowed tokens to **queue the call to ```emergencyExit()```** in ```SimpleGovernance``` contract. This will result in all funds being stolen from ```SelfiePool``` with **no cost to the attacker**