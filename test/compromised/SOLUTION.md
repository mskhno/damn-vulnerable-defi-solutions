## SOLUTION

From those 2 findings, it is obvious that the price of the NFT can be manipulated

To steal all the funds from ```Exchange.sol```, we need to buy NFT for the **lowest price possible**, and sell it for such price that we obtaing all of the contract's funds

To do that, the price must be manipulated. The following order of actions is needed to be taken to solve this level:
1. Set the price to **0.1 ether**, by manipulationg the trusted sources of ```TrustfulOracle.sol``` using their **leaked private keys**
2. Buy the NFT
3. Manipulate the price again, setting it to the full balance of ```Exchange.sol```
4. Sell the NFT
5. Return the price **back to its initial value**, to pass level's condition
6. Send funds to ```address recovery```
   
## FINDINGS

1. NFT price is **vulnerable to manipulation**

```Exchange.sol``` uses ```TrustfulOracle.sol``` to determine the price of the NFT it sells. The oracle has **only three sources** that are reporting on the price of that NFT

The protocol returns the median price, which in this case means that **2 out 3 sources need to be manipulated** to change the NFT price

2. Private keys of 2 sources are **leaked**

HTTP responce includes two hex strings that, when decoded from base64, give us 2 strings of 32 bytes. The two ```uint256``` variables are the **private keys of some of the sources** that report on the price of NFT

To check, whether these are private keys of those address or not, ```vm.addr``` can be used. It derives the address from the provided private key:
   1. The first hex string, when decoded, yields the byte string ```0x7d15bba26c523683bfc3dc7cdc5d1b8a2744447597cf4da1705cf6c993063744```. Using ```vm.addr``` retrieves the address ```0x188Ea627E3531Db590e6f1D71ED83628d1933088```
   2. The second one, ```0x68bd020ad186b647a691c6a5c0c1529f21ecd09dcc45241402ac60ba377c4159```, results into the address ```0xA417D473c40a4d42BAd35f147c21eEa7973539D8```

Those **addresses correspond with 2 sources** used in NFT price calculation
   