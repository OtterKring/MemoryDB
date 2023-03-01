#region CLASS_DEFINITIONS

#region INDEX_CLASS

#############################################
# INDEX class
#
# Builds a non-unique index for the data loaded in the main MemoryDB class.
# Supports adds, removes and updates
# Optionally CaseInsensitivity can be triggered for the index key
#

class Index {

    [string] $Key
    [bool] $CaseInsensitiveKey = $false

    # hidden $LookupTable = [System.Collections.Generic.SortedDictionary[string,System.Collections.Generic.List[PSObject]]]::new()
    hidden $LookupTable


    # Constructor taking the data to index and the desired index key as parameters.
    # the index will be set up case sensitive
    Index ( [PSObject[]]$Data, [string]$KeyString ) {

        $this.LookupTable = [System.Collections.Generic.SortedDictionary[string,System.Collections.Generic.List[PSObject]]]::new()
        $this.Init( $Data, $KeyString )

    }

    # Constructor taking the date to index, the desired index key and a boolean switch to choose
    # whether the index will treat the keys case insensitive or not as parameters
    Index ( [PSObject[]]$Data, [string]$KeyString, [bool]$CIK ) {

        if ( -not $CIK ) {
            $this.LookupTable = [System.Collections.Generic.SortedDictionary[string,System.Collections.Generic.List[PSObject]]]::new()
        } else {
            $this.CaseInsensitiveKey = $CIK
            $this.LookupTable = [System.Collections.Generic.SortedDictionary[string,System.Collections.Generic.List[PSObject]]]::new( [System.StringComparer]::CurrentCultureIgnoreCase )
        }

        $this.Init( $Data, $KeyString )

    }

    # helper initialization method to be used by multiple constructors
    hidden [void] Init ( [PSObject[]]$Data, [string]$KeyString ) {

        $this.Key = $this.GetProperty( $Data[0], $KeyString )

        if ( $this.Key ) {

            # if this index should work case insensitive, set the key to lower case
            # $this.Key = $this.CaseSafeKey( $this.Key )

            foreach ($set in $Data) {
                $this.AddEntry( $set )
            }
        } else {
            Throw "The given data does not contain the desired key `"$KeyString`"."
        }

    }

    # return the requested property name from a dataset to get its original case
    [string] GetProperty ( [PSObject]$DataSet, [string]$Property ) {

        return $DataSet.PSObject.Properties.Where{ $_.Name -eq $Property }.Name

    }

    # THIS IS >>>THE<<< METHOD to lookup data using thi index!
    [PSObject] Lookup ( [string] $SearchString ) {

        # $SearchString = $this.CaseSafeKey( $SearchString )
        return $this.LookupTable.$SearchString

    }

    # in case of a case-sensitive index this will still allow case-insensitive lookup.
    # NOTE: a unique key case sensitive index can provide multiple results in a case-insensitive search!
    [PSObject] CaseInsensitiveLookup ( [string] $SearchString ) {

        $Result = foreach ( $k in ($this.LookupTable.Keys.Where{$_ -eq $SearchString}) ) {
            $this.LookupTable.$k
        }

        return $Result

    }

    # add an entry for a given dataset to the index
    [void] AddEntry ( [PSObject]$DataSet ) {

        # get the index value from the dataset
        # $LookupValue = $this.CaseSafeKey( $DataSet.$($this.Key) )
        $LookupValue = $DataSet.$($this.Key)

        # if the index value already exists, add the dataset to its list of datasets (non-unique index)
        # if it doesn't, add a new index value and add the dataset there
        if ( $this.LookupTable.$LookupValue ) {
            $this.LookupTable.$LookupValue.Add( [PSCustomObject]$DataSet )
        } else {
            $this.LookupTable.Add( $LookupValue, [System.Collections.Generic.List[PSObject]]::new() )
            $this.LookupTable.$LookupValue.Add( [PSCustomObject]$DataSet )
        }

    }

    # remove the entry of a given dataset from the index
    [void] RemoveEntry ( [PSObject]$DataSet ) {

        # get the index value from the dataset
        # $LookupValue = $this.CaseSafeKey( $DataSet.$($this.Key) )
        $LookupValue = $DataSet.$($this.Key)

        # remove the dataset from the list at the index value
        $success = $this.LookupTable.$LookupValue.Remove( $DataSet )

        # if it worked, check if the index entry still contains other items (index is not unique)
        # if not, remove the index entry, complain if it doesn't work.
        if ($success) {

            if ( $this.LookupTable.$LookupValue.Count -eq 0 ) {

                $success = $this.LookupTable.Remove( $LookupValue )

                if ( -not $success ) {
                    Throw "Index `"$($this.Key)`": empty index entry `"$LookupValue`" could not be removed."
                }

            }

        } else {
            Throw "Index `"$($this.Key)`": dataset could not be removed from index entry `"$LookupValue`"."
        }

    }

    # update the index to reflect a change of a dataset
    # IF the value of this index in the new dataset has changed
    [void] UpdateEntry ( [PSObject]$oldDataSet, [PSObject]$newDataSet ) {

        # $oldLookupValue = $this.CaseSafeKey( $oldDataSet.$($this.Key) )
        # $newLookupValue = $this.CaseSafeKey( $newDataSet.$($this.Key) )
        $oldLookupValue = $oldDataSet.$($this.Key)
        $newLookupValue = $newDataSet.$($this.Key)

        # if new index values of the old and the new dataset are different, remove the old and add the new one
        # no need to do anything if they are equal, because the index only links to the original dataset,
        # where the values have already been updated
        if ( $oldLookupValue -ne $newLookupValue ) {
            $this.RemoveEntry( $oldDataSet )
            $this.AddEntry( $newDataSet )
        }

    }

    # checks, if a given key exists in the index
    [bool] ContainsKey ( [string]$Key ) {

        return $this.LookupTable.ContainsKey( $Key )

    }

    # if the index was created case sensitive,
    # this function allows checking for the existance of a key regardless of its case
    [bool] CaseInsensitiveContainsKey ( [string]$Key ) {

        return [bool]($this.LookupTable.Keys.Where{$_ -eq $Key}).Count

    }

    # if the index was set to be case insensitive,
    # this method converts the give key string to lower case
    # hidden [string] CaseSafeKey ( [string]$KeyString ) {

    #     if ( $KeyString -and $this.CaseInsensitiveKey ) {
    #         return $KeyString.ToLower()
    #     } else {
    #         return $KeyString
    #     }

    # }

}

#endregion INDEX_CLASS

#region UNIQUEINDEX_CLASS

##################################################################
# UNIQUEINDEX class, child of INDEX
#
# inherits from the INDEX class, but replaces Add and Remove method as well as the index dictionary with versions
# only supporting unique keys
#

class UniqueIndex : Index {

    # hidden [System.Collections.Generic.SortedDictionary[string,PSObject]] $LookupTable = [System.Collections.Generic.SortedDictionary[string,PSObject]]::new()
    hidden $LookupTable = [System.Collections.Generic.SortedDictionary[string,PSObject]]::new()

    # parameterless constructor, only necessary for inheritance
    UniqueIndex () {
        Write-Warning "The empty constructor of this class was created for technical reasons but has no valuable function."
        Write-Warning "Please use one of the following constructors:"
        Write-Warning '[UniqueIndex]::new( [PSObject]$DataSet", [string]$Key )'
        Write-Warning '[UniqueIndex]::new( [PSObject]$DataSet", [string]$Key , [bool]$CaseInsensitiveKey )'
    }

    # Constructor with dataset and key as parameters, redirects to base constructor
    # Index will use case sensitive keys
    UniqueIndex ( [PSObject]$Data, [string]$KeyString ) {

        $this.LookupTable = [System.Collections.Generic.SortedDictionary[string,PSObject]]::new()
        $this.Init( $Data, $KeyString )

    }

    # Constructor with dataset, key and case insensitivity switch as parameters, redirects to base constructor
    UniqueIndex ( [PSObject]$Data, [string]$KeyString, [bool]$CIK ) {

        if ( -not $CIK ) {
            $this.LookupTable = [System.Collections.Generic.SortedDictionary[string,PSObject]]::new()
        } else {
            $this.CaseInsensitiveKey = $CIK
            $this.LookupTable = [System.Collections.Generic.SortedDictionary[string,PSObject]]::new( [System.StringComparer]::CurrentCultureIgnoreCase )
        }

        $this.Init( $Data, $KeyString )
    }


    # Adding an entry to the index, pointing to the given dataset
    [void] AddEntry ( [PSObject]$DataSet ) {

        $SearchString = $DataSet.$($this.Key)
        $this.LookupTable.Add( $SearchString, $DataSet )

    }

    # Removing an entry from the index
    [void] RemoveEntry ( [PSObject]$DataSet ) {

        $SearchString = $DataSet.$($this.Key)
        $success = $this.LookupTable.Remove( $SearchString )

        if ( -not $success ) {
            Throw "UniqueIndex `"$($this.Key)`": index entry `"$SearchString`" could not be removed."
        }

    }

}

#endregion UNIQUEINDEX_CLASS

#region MEMORYDB_CLASS

################################################################################################
# MAIN MemoryDB Class
#
# Loads (preferably equally built) datasets to memory and create a unique (PrimaryKey) index for direct addressing.
# Optionally create more non-unique indices for directly address via other properties.
#

class MemoryDB {

    [string]$PrimaryKey
    [System.Collections.Generic.List[string]]$Indices = [System.Collections.Generic.List[string]]::new()
    [bool]$CaseInsensitiveKeys = $false

    hidden [System.Collections.Generic.List[PSObject]]$Data = [System.Collections.Generic.List[PSObject]]::new()
    hidden [UniqueIndex]$PK
    hidden [System.Collections.Generic.List[Index]]$IX = [System.Collections.Generic.List[Index]]::new()


    # Constructor taking the data to store and the name of the property, which should become the PrimaryKey, as parameters.
    # The MemoryDB will handle all keys case sensitive when this constructor is used.
    MemoryDB ( [PSObject[]]$Data, [string]$PrimaryKey ) {

        $this.Init( $Data, $PrimaryKey, $false )

    }

    # Constructor taking the data to store, the name of the property, which shoudl become the PrimaryKey and a boolean switch,
    # to choose whether the MemoryDB should treat the index keys case insensitive or not, as parameters
    MemoryDB ( [PSObject[]]$Data, [string]$PrimaryKey, [bool]$CaseInsensitiveKeys ) {

        $this.Init( $Data, $PrimaryKey, $CaseInsensitiveKeys )

    }

    # a helper initialization method to be used by multiple constructors
    hidden [void] Init ( [PSObject[]]$Data, [string]$PrimaryKey, [bool]$CaseInsensitiveKeys ) {

        # Get the requested Property from the given Data and it's original case
        $Key = $this.GetProperty( $Data[0], $PrimaryKey )

        # only build the DB if the property exits in the given data
        if ( $Key ) {

            # only build the DB if the property chosen as PrimaryKey is unique
            if ( $this.isUniqueProperty( $Data, $Key ) ) {

                # all good, save the property as PrimaryKey
                $this.PrimaryKey = $Key

                # add the given data to this instance of the class
                foreach ($set in $Data) {
                    $this.Data.Add( [PSCustomObject]$set )
                }

                # all data added, now build the PimaryKey-Index
                $this.PK = [UniqueIndex]::new( $this.Data, $this.PrimaryKey, $this.CaseInsensitiveKeys )

            } else {
                Throw "Property `"$PrimaryKey`" suggested for use as PrimaryKey is not unique."
            }

        }

    }

    # Add a dataset to the stored data and update the indices
    [void] AddDataset ( [PSObject]$DataSet ) {

        if ( $this.GetProperty( $DataSet, $this.PrimaryKey ) ) {

            if ( -not $this.Lookup($DataSet.$($this.PrimaryKey)) ) {

                # add the new dataset, so we have it together with the old data for PK uniqueness check
                $this.Data.Add( [PSCustomObject]$DataSet )

                # update PrimaryKey index
                $this.PK.AddEntry( $DataSet )

                # update all other indices (if any)
                foreach ($index in $this.IX) {
                    $index.AddEntry( $DataSet )
                }                
            } else {

                # remove new dataset from our data structure and complain
                [void]$this.Data.Remove( $this.Data[-1] )
                Throw "The new dataset cannot be added. PrimaryKey `"$($this.PrimaryKey)`" already exists."

            }

        } else {

            Throw "The new dataset cannot be added. PrimaryKey property `"$($this.PrimaryKey)`" is not present."

        }

    }

    # Remove a dataset from the stroed data and update indices
    [void] RemoveDataset ( [PSObject]$DataSet ) {

        # get the value of the primary key property from the give dataset
        $LookupValue = $DataSet.$($this.PrimaryKey)

        # get the original dataset from the stored data
        $Entry = $this.PK.Lookup( $LookupValue )

        # if a dataset was returned, continue, otherwise complain
        if ( $Entry ) {

            # remove the dataset from the stored data
            $success = $this.Data.Remove( $Entry )

            # if the removal worked, continue, otherwise complaine
            if ( $success ) {

                # remove the related entry fromt he primary key index
                $this.PK.RemoveEntry( $Entry )

                # remove the related entries from all other indices
                foreach ($index in $this.IX) {
                    $index.RemoveEntry( $Entry )
                }

            } else{
                Throw "MemoryDB: entry with primary key `"$LookupValue`" could not be removed."
            }

        } else {
            Throw "MemoryDB: no entry found for primary key `"$LookupValue`"."
        }

    }

    # Update a dataset in the stored data and update the indices
    [void] UpdateDataset ( [PSObject]$DataSet ) {

        # if the new dataset does not contain our primary key, we cannot know, which dataset to update
        if ( $this.GetProperty( $DataSet, $this.PrimaryKey ) ) {

            # check, if there already is a dataset with this primary key value. Replace, if yes, add as new dataset if no.
            $oldDataSet = $this.PK.Lookup( $DataSet.$($this.PrimaryKey) )
            if ( $oldDataSet ) {

                # Overwriting an already indexed cell of the data array, no changes to pk index necessary,
                # since it is only linking to the original data.
                $this.Data[ $this.Data.IndexOf( $oldDataSet ) ] = $DataSet

                # update all other indices
                foreach ($index in $this.IX) {
                    $index.UpdateEntry( $oldDataSet, $DataSet )
                }

            } else {

                # no existing dataset found with this PK value, so add it as a new entry
                $this.AddDataset( $DataSet )

            }

        } else {
            Throw "The new dataset does not contain the primarykey `"$($this.PrimaryKey)`"."
        }

    }

    # Get a dataset based on its primary key
    [PSObject] Lookup ( [string]$KeyString ) {

        return $this.PK.Lookup( $KeyString )

    }

    # Lookup datasets by primary key but ignore case, which could result in more than one result
    # if the database was set up with case sensitive keys
    [PSObject[]] CaseInsensitiveLookup ( [string]$KeyString ) {

        return $this.PK.CaseInsensitiveLookup( $KeyString )

    }

    # return the stored data "as is"
    [PSObject[]] GetRawData () {

        return $this.Data

    }

    # add a new non-unique index to the MemoryDB
    [void] NewIndex ( [string]$KeyString ) {

        if ( $this.Indices -notcontains $KeyString ) {

            $this.IX.Add( [Index]::new( $this.Data, $KeyString, $false) )
            $this.Indices.Add( $this.IX[-1].Key )

        } else {
            Throw "Index `"$KeyString`" already exists."
        }

    }

    # remove an existing non-unique index
    [void] RemoveIndex ( [string]$KeyString ) {

        $index = $this.GetIndices() | Where-Object Key -eq $KeyString

        if ( $index ) {

            $this.IX.RemoveAt( $index.Id )

            $success = $this.Indices.Remove( $this.Indices.Where{ $_ -eq $KeyString } )

            if (-not $success ) {
                Throw "MemoryDB: could not remove `"$KeyString`" from indices property."
            }

        } else {
            Throw "MemoryDB: index with key `"$KeyString`" not found."
        }

    }

    # list the optional non-unique indices with their sequence number and key name
    # DOES NOT INCLUDE the primary key index!
    [PSObject[]] GetIndices () {

        $Result = foreach ($index in $this.IX) {
            [PSCustomObject]@{
                Id = $this.IX.IndexOf( $index )
                Key = $index.Key
            }
        }

        return $Result

    }

    # get the give property name from a dataset to get its original case version
    hidden [string] GetProperty ( [PSObject]$DataSet, [string]$Property ) {

        return $DataSet.PSObject.Properties.Where{$_.Name -eq $Property}.Name

    }

    # test a property name against given data if it is unique
    hidden [bool] isUniqueProperty ( [PSObject[]]$Data, [string]$Property ) {

        $Multiples = $Data |
            Group-Object -Property $Property -NoElement |
            Where-Object Count -gt 1

        if (!$Multiples) {
            return $true
        } else {
            return $false
        }

    }

    # if the MemoryDB is created case insensitive, the method returns the given string in lower case
    # hidden [string] CaseSafeKey ( [string]$KeyString ) {

    #     if ( $KeyString -and $this.CaseInsensitiveKeys ) {
    #         return $KeyString.ToLower()
    #     } else {
    #         return $KeyString
    #     }

    # }

}

#endregion MEMORYDB_CLASS

#endregion CLASS_DEFINITIONS

#region WRAPPER_FUNCTIONS

###########################################################################
# FUNCTIONS for "User-Friendlyness"
#

#region NEW-MEMORYDB

<#
.SYNOPSIS
Create a new variable of type [MemoryDB] and fill it with initial data

.DESCRIPTION
Create a new variable of type [MemoryDB] and fill it with initial data

.PARAMETER Name
The name of the variabe

.PARAMETER Data
An array of Objects but at least one Dataset to initialize the MemoryDB

.PARAMETER PrimaryKey
Name of the property within the datasets to be used as PrimaryKey

.PARAMETER CaseInsensitiveKeys
Switch to set the MemoryDB to ignore case of the Keys (PrimaryKey, IndexKeys)

.PARAMETER Scope
Scope of the variable (Global, Local, Script)

.EXAMPLE
Get-ADUser -Filter 'Enabled -eq "true" -and Employeeid -like "1*" -Properties Employeeid | New-MemoryDB -Name 'AD' -PrimaryKey EmployeeId

.NOTES
2022-08-01 ... initial version by Maximilian Otter
#>
function New-MemoryDB {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory,ValueFromPipeline)]
        [PSObject[]]$Data,
        [Parameter(Mandatory)]
        [string]$PrimaryKey,
        [Parameter()]
        [switch]$CaseInsensitiveKeys,
        [Parameter()]
        [ValidateSet('Global','Local','Script')]
        [string]$Scope = 'Global'
    )

    begin {

        $memdb = Get-Variable -Name $Name -ValueOnly -ErrorAction SilentlyContinue
        # Do not overwrite anything existing with the same name with this function
        if ( $membdb ) {
            if ( $memdb.GetType().Name -eq "MemoryDB" ) {
                Throw "There already is a MemoryDB names `"$Name`". Please use `"Add-MemoryDBEntry`" to add additional data."
            } else {
                Throw "Another variable with name `"$Name`" already exists."
            }
        }

    }

    process {

        # get a reference to the existing MemoryDB variable (if there is one)
        $memdb = Get-Variable -Name $Name -ValueOnly -ErrorAction SilentlyContinue

        # if the MemoryDB exists, add the next dataset(s) from the pipeline
        # if not, create the variable with the given parameters
        if ( $memdb.Data.Count -gt 0) {
            foreach ($set in $Data) {
                $memdb.AddDataset( $set )
            }
        } else {
            if ($CaseInsensitiveKeys) {
                New-Variable -Name $Name -Scope $Scope -Value ( [MemoryDB]::new( $Data, $PrimaryKey, $CaseInsensitiveKeys ) )
            } else {
                New-Variable -Name $Name -Scope $Scope -Value ( [MemoryDB]::new( $Data, $PrimaryKey ) )
            }
        }

    }

}

#endregion NEW-MEMORYDB

#region TEST_MEMORYDB

<#
.SYNOPSIS
Test if a MemoryDB or other variable with the given name already exists

.DESCRIPTION
Test if a MemoryDB or other variable with the given name already exists, throw a terminating error if it does.

.PARAMETER Name
Name of the variable to check

.EXAMPLE
Test-MemoryDB -Name AD

.NOTES
2022-08-01 ... initial version by Maximilian Otter
#>
function Test-MemoryDB {
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )

    # get a reference to the existing MemoryDB
    $memdb = Get-Variable -Name $Name -ValueOnly -ErrorAction SilentlyContinue

    # Do not overwrite anything existing with the same name with this function
    if ( $memdb ) {
        if ( $memdb.GetType().Name -ne "MemoryDB" ) {
            Throw "`"$Name`" is not a MemoryDB."
        } else {
            $memdb
        }
    } else {
        Throw "MemoryDB `"$Name`" does not exist. Please use New-MemoryDB to create a MemoryDB."
    }

}

#endregion TEST_MEMORYDB

#region ADD_MEMORYDBENTRY

<#
.SYNOPSIS
Add a new dataset to a MemoryDB variable

.DESCRIPTION
Add one or more datasets to a MemoryDB variable

.PARAMETER Name
Name of the variable

.PARAMETER DataSet
one or an array of datasets to add

.EXAMPLE
Get-ADUser einstein -Properties EmployeeId | Add-MemoryDBEntry -Name AD

.NOTES
2022-08-01 ... initial version by Maximilian Otter
#>
function Add-MemoryDBEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory,ValueFromPipeline)]
        [PSObject[]]$DataSet
    )

    begin {

        # Test for the variable name so we don't overwrite something we shouldn't
        # get a reference to the existing MemoryDB
        $memdb = Test-MemoryDB -Name $Name

    }

    process {


        # add given dataset(s)
        foreach ($set in $DataSet) {
            $memdb.AddDataset( $set )
        }

    }

}

#endregion ADD_MEMORYDBENTRY

#region UPDATE-MEMORYDBENTRY

<#
.SYNOPSIS
Update a dataset in a MemoryDB variable

.DESCRIPTION
Update one or more datasets in a MemoryDB variable

.PARAMETER Name
Name of the variable

.PARAMETER DataSet
one or an array of datasets to update

.EXAMPLE
Get-ADUser einstein_new -Properties EmployeeId | Update-MemoryDBEntry -Name AD

.NOTES
2022-08-01 ... initial version by Maximilian Otter
#>
function Update-MemoryDBEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory,ValueFromPipeline)]
        [PSObject[]]$DataSet
    )

    begin {

        # Test for the variable name so we don't overwrite something we shouldn't
        # get a reference to the existing MemoryDB
        $memdb = Test-MemoryDB -Name $Name

    }

    process {

        # update given dataset(s)
        foreach ($set in $DataSet) {
            $memdb.UpdateDataset( $set )
        }

    }
}

#endregion UPDATE-MEMORYDBENTRY

#region REMOVE-MEMORYDBENTRY

<#
.SYNOPSIS
Remove a dataset from a MemoryDB variable

.DESCRIPTION
Remove one or more datasets from a MemoryDB variable

.PARAMETER Name
Name of the variable

.PARAMETER DataSet
one or an array of datasets to remove

.EXAMPLE
Get-ADUser einstein -Properties EmployeeId | Remove-MemoryDBEntry -Name AD

.NOTES
2022-08-01 ... initial version by Maximilian Otter
#>
function Remove-MemoryDBEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory,ValueFromPipeline)]
        [PSObject[]]$DataSet
    )

    begin {

        # Test for the variable name so we don't overwrite something we shouldn't
        # get a reference to the existing MemoryDB
        $memdb = Test-MemoryDB -Name $Name

    }

    process {

        # remove given dataset(s)
        foreach ($set in $DataSet) {
            $memdb.RemoveDataset( $set )
        }

    }

}

#endregion REMOVE-MEMORYDBENTRY

#region GET-MEMORYDBENTRY

<#
.SYNOPSIS
Query a dataset from a MemoryDB variable

.DESCRIPTION
Query one or more datasets from a MemoryDB variable using the default PrimaryKey or a chose precreated index.

.PARAMETER Name
Name of the variable

.PARAMETER KeyValue
One or more KeyValues of which to retrieve the dataset(s) for

.PARAMETER IndexName
Name of the Index / the indexed property to search in instead of the PrimaryKey index

.PARAMETER CaseInsensitiveLookup
Switch to trigger ignoring the case of the key

.EXAMPLE
'einstein','kepler' | Get-MemoryDBEntry -Name AD

Searches the MemoryDB "AD" for the dataset with PrimaryKey "einstein" and "kepler"

.EXAMPLE
'1002305','1000063' | Get-MemoryDBEntry -Name AD -IndexName EmployeeID

Searches the "EmployeeID" Index (if present) for the datasets with the given EmployeeID

.NOTES
2022-08-01 ... initial version by Maximilian Otter
#>
function Get-MemoryDBEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory,ValueFromPipeline)]
        [string[]]$KeyValue,
        [Parameter()]
        [string]$IndexName,
        [switch]$CaseInsensitiveLookup
    )

    begin {

        # Test for the variable name so we don't overwrite something we shouldn't
        # get a reference to the existing MemoryDB
        $memdb = Test-MemoryDB -Name $Name

        if ( $PSBoundParameters.ContainsKey('IndexName') -and $memdb.Indices -notcontains $IndexName ) {
            Throw "MemoryDB `"$Name`" does not contain an index for the property `"$IndexName`"."
        }

    }

    process {

        # loop through the given KeyValues (if provided as array)
        foreach ($value in $KeyValue) {

            # if no IndexName was provided, search in the PrimaryKey index
            if ( -not $PSBoundParameters.ContainsKey('IndexName') ) {

                # use case sensitive Lookup if not chose otherwise
                if ( -not $CaseInsensitiveLookup ) {
                    $memdb.PK.Lookup( $value )
                } else {
                    $memdb.PK.CaseInsensitiveLookup( $value )
                }

            } else {

                # use case sensitive Lookup if not chose otherwise
                if ( -not $CaseInsensitiveLookup ) {
                    $memdb.IX.Where{$_.Key -eq $IndexName}.Lookup( $value )
                } else {
                    $memdb.IX.Where{$_.Key -eq $IndexName}.CaseInsensitiveLookup( $value )
                }

            }

        }

    }

}

#endregion GET-MEMORYDBENTRY

#region GET-MEMORYDBINDEX

<#
.SYNOPSIS
List non-primary index/indices of a MemoryDB variable

.DESCRIPTION
List non-primary index/indices of a MemoryDB variable

.PARAMETER Name
Name of the variable

.PARAMETER IndexName
Name(s) of the index/indexed property

.EXAMPLE
Get-MemoryDBIndex -Name AD -IndexName SamAccountName

.NOTES
2022-08-01 ... initial version by Maximilian Otter
#>
function Get-MemoryDBIndex {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(ValueFromPipeline)]
        [string[]]$IndexName
    )

    begin {

        # Test for the variable name so we don't overwrite something we shouldn't
        # get a reference to the existing MemoryDB
        $memdb = Test-MemoryDB -Name $Name

        $Indices = $memdb.IX

    }

    process {

        if ( $PSBoundParameters.ContainsKey('IndexName') ) {

            foreach ($index in $IndexName){
                $Indices.Where{$_.Key -eq $IndexName}
            }

        } else {
            $Indices
        }

    }

}

#endregion GET-MEMORYDBINDEX

#region NEW-MEMORYDBINDEX

<#
.SYNOPSIS
Create a new non-unique index on MemoryDB variable

.DESCRIPTION
Create one or more new non-unique indices on MemoryDB variable

.PARAMETER Name
Name of the MemoryDB variable

.PARAMETER IndexName
Name of the new index ( and the name of the property to user for the index )

.EXAMPLE
'UserPrincipalName','SamAccountName' | New-MemoryDBIndex -Name AD

.NOTES
2022-08-01 ... initial version by Maximilian Otter
#>
function New-MemoryDBIndex {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory,ValueFromPipeline)]
        [string[]]$IndexName
    )

    begin {

        # Test for the variable name so we don't overwrite something we shouldn't
        # get a reference to the existing MemoryDB
        $memdb = Test-MemoryDB -Name $Name

    }

    process {

        foreach ($index in $IndexName) {

            $memdb.NewIndex( $index )

        }

    }
}

#endregion NEW-MEMORYDBINDEX

#region REMOVE-MEMORYDBINDEX

<#
.SYNOPSIS
Remove a non-unique secondary index from a MemoryDB variable

.DESCRIPTION
Remove one or more non-unique secondary indices from a MemoryDB variable

.PARAMETER Name
Name of the MemoryDB variable

.PARAMETER IndexName
Name of the index to remove

.EXAMPLE
'UserPrincipalName','EmployeeID' | Remove-MemoryDBIndex -Name AD

.NOTES
2022-08-01 ... initial version by Maximilian Otter
#>
function Remove-MemoryDBIndex {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory,ValueFromPipeline)]
        [string[]]$IndexName
    )

    begin {

        # Test for the variable name so we don't overwrite something we shouldn't
        # get a reference to the existing MemoryDB
        $memdb = Test-MemoryDB -Name $Name

    }

    process {

        foreach ($index in $IndexName) {

            $memdb.RemoveIndex( $index )

        }

    }
}

#endregion REMOVE-MEMORYDBINDEX


#endregion WRAPPER_FUNCTIONS