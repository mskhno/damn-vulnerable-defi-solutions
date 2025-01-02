## SOLUTION

1. Create a contract, which call ```flashLoan()``` with such arguments, that it approves this contract to spend any amount of tokens of supported asset

Trasnfer those tokens to the designated address

All of this should be implementer inside of the ```constructor()``` function, so that we use only 1 transaction


## FINDINGS

1. Anybody can approve anybody to **spend all of TrusterLenderPool's tokens**

```flashLoan()``` function makes a low-level call to ```address target``` with ```bytes memory data``` as calldata. In this call, contract expects users to return borrowed tokens

However, **nothing prohibits malicious calls** made from TrusterLenderPool to other contract

This results into a situation, in which any address can call ```flashLoan()``` function with such arguments, that the ```target.functionCall(data)``` results into TrusterLenderPool approving some address for some amount of tokens, that are encoded into ```bytes memory data``` argument as calldata for this call

This allows **any address to steal all tokens** used as asseet on TrusterLenderPool, using ```transferFrom()``` on the token contract

1. For the flash loan functionality to work, ```flashLoan()``` **expects** the user to manually transfer the tokens back

It tries to ensure that by imposing a balance check, which reverts if the balance after the trasfer is not the same
