# PS_MemoryDB
Module for an in-memory quasi-database, enabling fast access via multiple indices


# Why?

No matter how optimized your script is, there is always one thing slowing it down: calls to external data sources. Especially when you are dealing with cloud resources.

They can be pretty quick delivering a big load of data in one call, but a single call still can take seconds to complete. You definitely want to avoid doing that more often in one script.

Even fast database system or the quite performance optimized Active Directory can drag you script down if you call it multiple time, especially when queying non-indexed fields.

## Example: Active Directory Performance
<small>(All measurements taken in Windows PowerShell 5.1)</small>

Just for testing lets create a variable `$AD` containing a bunch of `SamAccountName`s (an indexed field) and `EmployeeId`s (not indexed in Active Directory):

```
$ADSearchData = Get-ADUser -SearchBase 'ou=users,ou=finance,dc=mydomain,dc=net' -Filter 'EmployeeId -like "*"' -Properties EmployeeId | Select-Object SamAccountName,EmployeeId
```

### calling Active Directory directly

Now lets measure, how long 1000 calls to Active Directory take filtering for either one of the properties. I use `Get-Random` for each call, so Active Directory does not get used to what we are doing and starts caching:

```
Measure-Command { foreach ($null in 1..1000) { Get-ADUser -Filter "SamAccountName -eq '$(Get-Random $ADSearchData.SamAccountName)'" } }


Days              : 0
Hours             : 0
Minutes           : 0
Seconds           : 10
Milliseconds      : 28
Ticks             : 100284502
TotalDays         : 0.000116070025462963
TotalHours        : 0.00278568061111111
TotalMinutes      : 0.167140836666667
TotalSeconds      : 10.0284502
TotalMilliseconds : 10028.4502


Measure-Command { foreach ($null in 1..1000) { Get-ADUser -Filter "EmployeeId -eq '$(Get-Random $ADSearchData.EmployeeId)'" } }


Days              : 0
Hours             : 0
Minutes           : 39
Seconds           : 58
Milliseconds      : 359
Ticks             : 23983594472
TotalDays         : 0.0277587898981481
TotalHours        : 0.666210957555555
TotalMinutes      : 39.9726574533333
TotalSeconds      : 2398.3594472
TotalMilliseconds : 2398359.4472
```


10 seconds vs. ~40 **minutes**! I guess it's more than obvious that making several calls searching for an EmployeeId leads to rather unpleasant performance. Of course you could index the field in the database, too. But - hey - I am not the DB admin here, am I?

This is where caching data upfront can *really* speed things up. Given, you will not be working with the live data, so if anything changes while your script is running, it will not be taken into account. But how much of a risk this is for your script during the given runtime is something only you can decide.

### simple variable caching

If you don't care for any bells and whistles you can just cache the data you need to a variable, like:

```
$AllAD = Get-ADUser -Properties DisplayName,EmployeeID | Select-Object DisplayName,SamAccountName,EmployeeID,Enabled

# took ~15 sec
```

... and then use the usual PowerShell options to search for the data you want:

```
$AllAD | Where-Object EmployeeID -eq '17010042'        # 200ms

# or

$AllAD.Where{ $_.EmployeeID -eq '17010042' }           # 400ms

# or 

foreach ($user in $AllAD) { if ($user.EmployeeId -eq '17010042') { $user; break } }    # 46ms
```

If you only expect one result anyway you could speed up the `foreach` even more by adding a break in the `if` clause, but I guess you get the point already.

1000 searches for a random EmployeeId (with the `break`) like we did before are now done in ~16s on my machine. A lot better than the 40min from before!

### using the MemoryDB module

