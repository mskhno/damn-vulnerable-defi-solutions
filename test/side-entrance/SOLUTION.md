## SOLUTION

1. Create a contract compliant with ```IFlashLoanEtherReceiver``` interface to execute a flash loan through it

During, the ```execute()``` call from SideEntranceLenderPool, deposit the borrowed funds

After the flash loan execution finishes, call ```withdraw()``` and send received ETH to ```address recovery```

## FINDINGS

1. A**nyone can claim ownership of funds** during ```flashLoan()``` call

T```flashLoan()``` function optimistically send ETH to the ```msg.sender``` during the call

To ensure that the funds are returned, it compares the ```balanceBefore``` variable, set as the ether balance of the contract before transfering to funds, to the balance of the contract after the external interface call, which hands over the control to execute some logic with sent funds

However, the **contract just expects those balances to be the same**, disregarding **the way those funds are returned**. Contract expects that during ```IFlashLoanEtherReceiver(msg.sender).execute{value: amount}()``` call funds are returned, but **the only way to do return funds** is for the contract on ```msg.sender``` address to call ```deposit()``` function, since neither ```receive()``` nor ```fallback()``` functions are defined

This results into the situation, where **the caller of ```flashLoan()``` deposits borrowed funds**, allowing them to steal it afterwards