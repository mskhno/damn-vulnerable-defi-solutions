## SOLUTION

To execute the attack, ```UniswapV2Pair``` pool prive has to be shifted, such that the ```DVT``` token here becomes **much cheaper**

This would allow to borrow tokens **with a much lower deposit** on ```PuppetV2Pool``` contract

To do this, complete the following order of transactions: 
1. Buy up ```WETH``` from ```UniswapV2Pair``` pool to decrease the price of ```DVT```
2. Borrow all ```DVT``` token at much cheaper deposit of ```WETH``` from ```PuppetV2Pool```
3. Send ```DVT``` to ```recovery``` address
 
## FINDINGS

1. ```PuppetV2Pool``` is vulnerable to **oracle manipulation attack**

The pool calculates the deposit requiered for borrowing ```DVT``` tokens by **fetching the spot price from the single source**

In this case, ```UniswapV2Pair``` pool is the only source the ```PuppetV2Pool`` contract gets its price from

Vulnerability lies **in centralization and the size of the reporting pool**. It has ```WETH``` and ```DVT``` tokens with their reserves being just 10 ```WETH``` and 100 ```DVT``` tokens 

That fact means that is is very easy to lower the price of ```DVT token```, therefore  ** the ```WETH``` deposit requiered for borrowing tokens on ```PuppetV2Pool```