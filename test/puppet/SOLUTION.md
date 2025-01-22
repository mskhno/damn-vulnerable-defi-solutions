## SOLUTION

To pass this challenge, **oracle manipulation** and borrowing of the tokens has to be performed in **a single transaction**

Stealing form ```PuppetPool``` contract boils down the following logic:
1. Buy as much ETH from the ```PuppetPool``` until the price of ```DVT``` is such that deposit is **low enough or the lowest** it can be
2. Borrow ```DVT``` from the pool, providing ```recovery``` as the recepient of the tokens
   
However, this logic requires multiple approval transactions and calls to be made, therefore not passing the s**ingle transaction requierement**

To solve the level, ```permit()``` function can be used in combination with creating a contract that would execute the transactions for us. For this:

1. Create a signature for ```permit()``` function on ```DVT``` token contract that is valid for the **predicted address of the contract** executing the logic
2. Deploy the contract with **the logic of the attack**, pass the signature to it and call ```permit()``` function, allowing the contract to use ```player``` account ```DVT``` tokens. ```constructor()``` must be ```payable``` to provide ETH for deposit

In this case, ```player``` address single transaction is **contract creation**

## FINDINGS

1. ```PuppetPool``` pool is vulnerable to **oracle manipulation attack**

This contract calculates the deposit amount of ETH needed to borrow some amount of ```DVT``` tokens by fetching the price of ```DVT``` from **a single** ```UniswapV1Pair``` **pool** and increasing it by 2

However, the deposit value can be decreased greatly by **buying up ETH** from ```UniswapV2Pair``` contract, which would result into ```DVT``` **price plummeting** on this pool, therefore allowing to borrow those tokens from ```PuppetPool`` pool for a much lower amount of ETH