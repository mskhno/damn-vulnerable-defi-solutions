## SOLUTION

To solve this level, we have to send all saved NFTs to the ```FreeRiderRecoveryManager``` contract and get paid the ```BOUNTY``` of 45 ETH

The vulnerability in the marketplace allows us to buy all of the tokens not for 90 ETH, but **just for 15**. But the problem is - we **do not have enough** ETH

In the test set up, we can find that there is also a ```UniswapV2Pair``` contract deployed, which **has the flash swap** functionality. Using this, we will **acquire the ETH we need** and solve this challange

To do some, the following logic must be executed:
1. Create a contract that **can use flash swaps** on ```UniswapV2Pair``` contract and **can receive NFTs** via ```safeTransferFrom```. Points listed below need to be implemented:
    - The contract **must have** ```uniswapV2Call()``` function to receive the funds on the callback from the pool
    - **Inherit** ```IERC721Receiver``` interface
    - Contract approves the ```player``` address for all of its tokens
2. Buy all NFTs for 15 ETH using the contract
3. As ```player``` address, use ```safeTransferFrom()``` to move NFTs from the contract we created to the ```FreeRiderRecoveryManager```
    - We do it in this way, so that the ```onERC721Received()``` function if triggered on ```FreeRiderRecoveryManager``` contract, which handles the ```BOUNTY``` payout

## FINDINGS

1. Anybody can **buy all NFTs** for the **price of one**

The way function ```_buyOne()``` checks if sent amount of ETH is enough to buy NFTs is wrong

Function compares the **price for only one NFT** to the ```msg.value``` sent along with the call, allowing the attacker to buy multiple NFTs, but **paying only for the most expensive** one

The better way to do this is to calculate **the cummulitive price of all NFTs**, and if ```msg.value``` is enough, **then execute** the call

1. Contract **pays the price to the buyer** of the NFT, **not the seller** of the token

```_buyOne()``` function has bad ordering of the transactions for transfering the NFT and paying for it

It send the price for the NFT **to the current owner** of the token, retrieved with the ```_token.ownerOf(tokenId)``` call. But, the ```FreeRiderNFTMarketplace``` contract **does so after transfering the token** to the buyer

In this case **the owner is updated** to be the ```msg.sender``` of the call, e.g. the buyer, and then the contract sends ETH to this new owner address

To fix this, those two calls **must be reordered** so that the marketplace contract **sends the money first**, and only **after that the token can be trasfered** using ```safeTransferFrom()``` function to the ```msg.sender```