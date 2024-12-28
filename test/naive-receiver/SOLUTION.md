## SOLUTION

1. **Drain WETH** from FlashLoanReceiver to NaiveReceiverPool, by using ```multicall()``` to call ```flashLoan()``` function with FlashLoanReceiver as ```IERC3156FlashBorrower receiver``` argument

```onFlashLoan()``` **does not verify the initiator** of the flash loan, allowing any address to call ```flashLoan()``` and force FlashLoanReceiver to pay 1 WETH per each type of this call

2. Call ```withdraw()``` function on NaiveReceiverPool through BasicForwarders ```execute()``` calling ```multicall()``` function, **draining all funds** to ```address recovery```

Vulnerability here lies in context manipulation to provide the right ```msg.data``` to ```_msgSender()``` for it to return ```address deployer``` to ```withdraw()``` function

All the funds are deposited in the name of ```address deployer```, so the only way on this contract to move WETH if for this address to call ```withdraw()```

At the same time, ```_msgSender()``` is used to determine the sender of the call and it has custom logic to do this. For calls where ```msg.sender == trustedForwarder && msg.data.length >= 20```, it returns the last 20 bytes of ```msg.data``` provided

Using BasicForwarder contract and multicall functionality, **we can manipulate ```msg.data``` for ```_msgSender()```**

We need to create a such call, that the following points are met:
- Call to ```withdraw()``` comes from BasicForwarder
- The last 20 bytes of the ```msg.data``` for ```_msgSender()``` must be ```address deployer```

To do this, call ```execute()``` on BasicForwarder with such ```Request``` struct, so that BasicForwarder calls ```multicall()``` on NaiveReceiverPool. This will delegate call to the ```withdraw()```, which keeps ```msg.sender``` as BasicForwarder, but **substitutes the ```msg.data``` to be ```bytes[] memory data```** argument for the ```multicall()```, where the last 20 bytes are ```address deployer```

## FINDINGS

1. **Anyone can drain WETH** from FlashLoanReceiver to NaiveReceiverPool

```onFlashLoan()``` function in FlashLoanReceiver **does not verify** the ```address initiator``` variable, allowing unauthorized calls to it through ```flashLoan()`` on NaiveReceiverPool

This means that anyone can call ```flashLoan()``` on NaiveReceiverPool contract and provide FlashLoanReceiver as ```address receiver``` argument, causing **1 WETH being drained** in the form of fixed fee to the NaiveReceiverPool per each ```flashLoan()``` call. This can be also done in one call, using ```multicall()` function on NaiveReceiverPool contract

2. ```_msgSender()``` on calls from BasicForwarder may return **arbitrary address**

```execute()``` function construct the payload for the call defined in ```Request``` struct provided for the call. The calldata is defined as ```payload = abi.encodePacked(request.data, request.from)```, which allows user to set up this data

It is not clear to me now how to do it, but maybe it is possible to call ```withraw()``` on NaiveReceiverPool with BasicForwader, so that we can steal fund form ```address deployer``` on NaiveReceiverPool.

On the other hand, ```_msgSender()``` returns the last 20 bytes, which are defined as shown prevously - by packing together ```request.data``` and ```request.from```

This vector may be considered later, although it is probably not achievable to steal funds in this way

3. ```_msgSender``` has custom logic to retrieve the address for calls, where```msg.sender == trustedForwarder && msg.data.length >= 20```

My thought here is the next: what would the ```msg.data``` be here during ```execute()``` call to ```multicall()``` on NaiveReceiverPool?

```execute()``` function would provide the ```msg.data``` in ```multicall()```, the **this function then makes delegate calls to itself**, e.g NaiveReceiverPool delegate call NaiveReceiverPool with ```bytes[] memory data``` provided to ```multicall()```

Therefore, if I am not mistaken, if ```multicall()``` in its turn call ```withdraw()```, then ```_msgSender()``` should receive its ```msg.data`` being the data for the delegate call

In other way, in such situation ```bytes[] memory data``` is ```msg.data``` inside ```withdraw()``` call on NaiveReceiverPool

As stated before, ```_msgSender()``` returns the last 20 bytes in this case, so can we set it up to ```address deployer```?