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

# 12000+ entries, took ~15 sec
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

# Using the MemoryDB module

The MemoryDB module is maybe a bit of an overkill for the given example, but it nevertheless provides the same advantages, adding the possibility to define multiple indices for fast access to your data and not being restricted to only one "search property".

The module was initially designed to be class-based, but to make it easier to use for non-class people I added a couple of wrapper functions which may eat up some performance compared to the pure class usage but on the other hand provide pipeline support.

## Initialize your MemoryDB

After importing the module you can start straight away with the functions the module provides.

If you want to use the classes directly you must run "`using module <path to memorydb module>`" after the import.

1) Load your initial data

```
#####
# using the function, takes ~1.5min for me

Get-ADUser -Filter * -Properties DisplayName,EmployeeID | Select-Object DisplayName,SamAccountName,EmployeeID,Enabled | New-MemoryDB -Name AllAD -PrimaryKey SamAccountName

#####
# using the class, which requires having the data in an array at first

# ~15 sec
$ADData = Get-ADUser -Filter * -Properties DisplayName,EmployeeID | Select-Object DisplayName,SamAccountName,EmployeeID,Enabled

# ~26 sec
$AllAD = [memorydb]::new( $ADData, 'SamAccountName' )
```

Using the class is a lot faster than using the function, since it loads all the data in one run, checking for uniqueness of the PrimaryKey using the full array, while the function, to make pipelining possible, adds the datasets one by one checking each for providing a unique value for the primary key. It uses less memory, though, since it does not require the data preloaded.

### why is loading the MemoryDB slower than simple variable caching?

Compared to the simple caching in the example used to show the performance differences loading the MemoryDB is still a bit slower, even if you use the class, because, while in our simple caching example you just push the data straight to an array without bells and whistles, the MemoryDB uses a SortedDictionary, so it checks the uniqueness of each key added, sorts the entries while they are being added and creates the primary key index along the way.

2) Add additional indices (optional)

While the primary key index is created immediately when loading the MemoryDB or adding a dataset, additional indices are optional and can be created or removed whenever you want. Once they are created they are updated automatically whenever a change in the MemoryDB is done.

```
#####
# using the function, ~55 seconds

New-MemoryDBIndex -Name AllAD -IndexName DisplayName


#####
# using the class, ~ 9 seconds

$AllAD.NewIndex('EmployeeID')
```

I admit I was a little bit surprised about the speed difference here, since the function doesn't do more than calling the class. I suppose it is linked to the more displaynames being more complex data than the employeeids and thus take more effort for sorting.
Additionally you may already have notices, that DisplayName will not be a unique index. The additional indices are not unique and can return multiple datasets for a key.

### aren't these indices wasting a lot of memory?

Yes and no.

The key fields are duplicated, of course, because the provide the value the SortedDictionary uses to sort and retrieve its data. The actual dataset indexed is linked "by reference", so the index just points to the original dataset but does not hold its own copy. The advantage of this, apart from the memory usage, is, that all changes done in the data are immediately visible in the index, too.
Linking to the cells of an array is default behavior of Powershell. While often loathed for making actually copying arrays a tedious process, it is a welcome feature here.

## Looking up data

### Querying a Primary Key

```
#####
# using the function; 1000 random calls = ~5sec

Get-MemoryDBEntry -Name AllAD -KeyValue 'einstein'

#####
# using the class; 1000 random calls = ~4sec

$AllAD.Lookup( 'einstein' )
```

### Querying an optional Index

```
#####
# using the function; 1000 random calls = 5.5sec

Get-MemoryDBEntry -Name AllAD -KeyValue '17010042' -IndexName EmployeeID

#####
# using the class
#
# ... with ANY index; 1000 random calls = 4sec

$AllAD.IX.Lookup( '17010042' )

# ... with a SPECIFIC index

# if you want to know the array index of your desired index:

$AllAD.GetIndices()

Id Key
-- ---
 0 EmployeeID
 1 DisplayName

# choose one of the two; 1000 random calls = 3.5sec 

$AllAD.IX[0].Lookup( '17010042' )
$AllAD.IX.Where{$_.Key -eq 'EmployeeID'}.Lookup( '17010042' )
```

**Now we are talking!**

This is were even the `foreach` loop in our simple caching example falls back, taking ~3 times longer for 1000 queries, let alone the 40min it took AD to deliver the unindexed field.

## Case Sensitivity

<hr>
<div align=center>

**ATTENTION classic PowerShell users!**
</div>

Since MemoryDB is using a `System.Collections.Generic.SortedDictionary<T>` as its base data type
**it is case sensitive by default!**

This means it is not the same querying for `einstein@mydomain.net` or `einstein@MYDOMAIN.NET`!
<hr>

It is nevertheless possible to either ...
* create the MemoryDB case **in**sensitive

```
$AllAD = [memorydb]::new( $Data, 'SamAccountName', $true )

# or

$Data | New-MemoryDB -Name AllAD -PrimaryKey SamAccountName -CaseInsensitiveKeys
```

* or ignore the case during lookup

```
$AllAD.CaseInsensitiveLookup('einstein')
$AllAD.IX.Where{$_.Key -eq 'DisplayName'}.CaseInsensitiveLookup('einstein albert')

# or

Get-MemoryDBEntry -Name AllAD -KeyValue einstein -CaseInsensitiveLookup
Get-MemoryDBEntry -Name AllAD -KeyValue 'einstein albert' -IndexName DisplayName -CaseInsensitiveLookup
```

**NOTE:** doing a case insensitive lookup in a case sensitive MemoryDB may return multiple results (e.g. you will get the entry for 'EINSTEIN Albert' and 'Einstein Albert' if both are present). Be sure to take care of that.

## Adding, Updating, Removing

### ... Datasets

<table>
    <tr>
        <th> Class </th>
        <th> Function </th>
    </tr>
    <tr>
        <td> $AllAD.AddDataset( $set ) </td>
        <td> New-MemoryDBEntry -Name AllAD -DataSet $set </td>
    </tr>
    <tr>
        <td> $AllAD.UpdateDataset( $set ) </td>
        <td> Update-MemoryDBEntry -Name AllAD -DataSet $set </td>
    </tr>
    <tr>
        <td> $AllAD.RemoveDataset( $set ) </td>
        <td> Remove-MemoryDBEntry -Name AllAD -DataSet $set </td>
    </tr>
</table>


### ... Indices

<table>
    <tr>
        <th> Class </th>
        <th> Function </th>
    </tr>
    <tr>
        <td> $AllAD.NewIndex( $Propertyname ) </td>
        <td> New-MemoryDBIndex -Name AllAD -IndexName $Propertyname </td>
    </tr>
    <tr>
        <td> $AllAD.RemoveIndex( $Propertyname ) </td>
        <td> Remove-MemoryDBIndex -Name AllAD -IndexName $Propertyname </td>
    </tr>
</table>

There is no "updating" for indices, since this is done in the background when needed, but you can have the MemoryDB show you the current indices:

<table>
    <tr>
        <th> Class </th>
        <th> Function </th>
    </tr>
    <tr>
        <td> $AllAD.GetIndices() </td>
        <td> Get-MemoryDBIndex -Name AllAD [-IndexName $Propertyname] </td>
    </tr>
</table>


<hr>
<p align=right>Maximilian Otter 2022-08-02</p>