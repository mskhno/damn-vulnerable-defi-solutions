## SOLUTION

1. Send DVT tokens directly to Vault contract, to force it's shares amount and it's balance of asset token to go out of sync, causing line 85 to revert.

Attack: just send DVT tokens.

## FINDINGS

Vault has its own token to represent shares of assets deposited by users
DVT is a different token, but **it is the asset** of the Vault

1. Sending DVT to Vault directly will halt flash loan functionality

On lines 84-85, ```flashLoan()``` checks for assets and shares to be same amount

The assets are defined as the Vault's balance of DVT token, since it is set to be the asset of the Vault and totalAssets() is overriden to call  ```asset.balanceOf(address(this))```

Contract compares this to ```convertToShares(totalSupply)```. This returns the total amount of shares that Vault contract has minted for depositing the asset. 

This check fails if total amount of shares goes out of sync with the asset balance of the Vault.

The issue is that the Vault contract **does not** mint shares on tokens set directly to it, nor in some way prohibits from sending those tokens in a direct way.
