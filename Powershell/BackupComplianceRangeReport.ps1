<#

.SYNOPSIS
This script will extract compliance and snapshot information for all CDM clusters in a given RSC environment. 

.EXAMPLE
./ChristmasTreeReport.ps1 -ServiceAccountJson /Users/Rubrik/Documents/ServiceAccount.json -daysToReport 7

This will generate a list of objects and their compliance status over the last 7 days. In the event there are missed snapshots, snapshot information relative to the date range specified will be pulled and complied into a single report.


.EXAMPLE
./ChristmasTreeReport.ps1 -ServiceAccountJson /Users/Rubrik/Documents/ServiceAccount.json -daysToReport 7 -ClusterId "3bc43be7-00ca-4ed8-ba13-cef249d337fa,39b92c18-d897-4b55-a7f9-17ff178616d0"

This will generate a list of objects and their compliance status over the last 7 days. In the event there are missed snapshots, snapshot information relative to the date range specified will be pulled and complied into a single report. This will also filter to only the clusterUUIDs specified 

.NOTES
    Author  : Marcus Henderson <marcus.henderson@rubrik.com> in collaboration with Reggie Hobbs
    Created : March 22, 2023
    Company : Rubrik Inc

#>



<#

Features to Add:
Filtering based on cluster

Add in summary view of backups 


#>

[cmdletbinding()]
param (
    [parameter(Mandatory=$true)]
    [string]$ServiceAccountJson,
    [parameter(Mandatory=$true)]
    [string]$daysToReport,
    [parameter(Mandatory=$false)]
    [string]$ClusterId

)

##################################

# Adding certificate exception to prevent API errors

##################################
if ($IsWindows -eq $true){
  add-type @"

    using System.Net;

    using System.Security.Cryptography.X509Certificates;

    public class TrustAllCertsPolicy : ICertificatePolicy {

        public bool CheckValidationResult(

            ServicePoint srvPoint, X509Certificate certificate,

            WebRequest request, int certificateProblem) {

            return true;

        }

    }

"@

  [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

}

if($IsMacOS -eq $true){
  #Do Nothing for now
}

$serviceAccountObj = Get-Content $ServiceAccountJson | ConvertFrom-Json
$Output_directory = (Get-Location).path
$mdate = (Get-Date).tostring("yyyyMMddHHmm")
function connect-polaris {

    # Function that uses the Polaris/RSC Service Account JSON and opens a new session, and returns the session temp token

    [CmdletBinding()]

    param (

        # Service account JSON file

    )

   

    begin {

        # Parse the JSON and build the connection string

        #$serviceAccountObj 

        $connectionData = [ordered]@{

            'client_id' = $serviceAccountObj.client_id

            'client_secret' = $serviceAccountObj.client_secret

        } | ConvertTo-Json

    }

   

    process {

        try{

            $polaris = Invoke-RestMethod -Method Post -uri $serviceAccountObj.access_token_uri -ContentType application/json -body $connectionData

        }

        catch [System.Management.Automation.ParameterBindingException]{

            Write-Error("The provided JSON has null or empty fields, try the command again with the correct file or redownload the service account JSON from Polaris")

        }

    }

   

    end {

            if($polaris.access_token){

                Write-Output $polaris

            } else {

                Write-Error("Unable to connect")

            }

           

        }

}
function disconnect-polaris {

    # Closes the session with the session token passed here

    [CmdletBinding()]

    param (
    )

   

    begin {

 

    }

   

    process {

        try{

            $closeStatus = $(Invoke-WebRequest -Method Delete -Headers $headers -ContentType "application/json; charset=utf-8" -Uri $logoutUrl).StatusCode

        }

        catch [System.Management.Automation.ParameterBindingException]{

            Write-Error("Failed to logout. Error $($_)")

        }

    }

   

    end {

            if({$closeStatus -eq 204}){

                Write-Output("Successfully logged out")

            } else {

                Write-Error("Error $($_)")

            }

        }

}
function Get-ClusterInfo{
    try{
        $query = "query ClusterListTableQuery(`$first: Int, `$after: String, `$filter: ClusterFilterInput, `$sortBy: ClusterSortByEnum, `$sortOrder: SortOrder, `$showOrgColumn: Boolean = false) {
            clusterConnection(filter: `$filter, sortBy: `$sortBy, sortOrder: `$sortOrder, first: `$first, after: `$after) {
              edges {
                cursor
                node {
                  id
                  ...ClusterListTableFragment
                  ...OrganizationClusterFragment @include(if: `$showOrgColumn)
                }
              }
              pageInfo {
                startCursor
                endCursor
                hasNextPage
                hasPreviousPage
              }
              count
            }
          }
          
          fragment OrganizationClusterFragment on Cluster {
            allOrgs {
              name
            }
          }
          
          fragment ClusterListTableFragment on Cluster {
            id
            name
            pauseStatus
            defaultAddress
            ccprovisionInfo {
              progress
              jobStatus
              jobType
              __typename
            }
            estimatedRunway
            geoLocation {
              address
              __typename
            }
            ...ClusterCardSummaryFragment
            ...ClusterNodeConnectionFragment
            ...ClusterStateFragment
            ...ClusterGlobalManagerFragment
            ...ClusterAuthorizedOperationsFragment
            ...ClusterVersionColumnFragment
            ...ClusterTypeColumnFragment
            ...ClusterCapacityColumnFragment
          }
          
          fragment ClusterCardSummaryFragment on Cluster {
            status
            systemStatus
            systemStatusAffectedNodes {
              id
            }
            clusterNodeConnection {
              count
            }
            lastConnectionTime
          }
          
          fragment ClusterNodeConnectionFragment on Cluster {
            clusterNodeConnection {
              nodes {
                id
                status
                ipAddress
              }
            }
          }
          
          fragment ClusterStateFragment on Cluster {
            state {
              connectedState
              clusterRemovalState
            }
          }
          
          fragment ClusterGlobalManagerFragment on Cluster {
            passesConnectivityCheck
            globalManagerConnectivityStatus {
              urls {
                url
                isReachable
              }
            }
            connectivityLastUpdated
          }
          
          fragment ClusterAuthorizedOperationsFragment on Cluster {
            authorizedOperations {
              id
              operations
            }
          }
          
          fragment ClusterVersionColumnFragment on Cluster {
            version
          }
          
          fragment ClusterTypeColumnFragment on Cluster {
            name
            productType
            type
            clusterNodeConnection {
              nodes {
                id
              }
            }
          }
          
          fragment ClusterCapacityColumnFragment on Cluster {
            metric {
              usedCapacity
              availableCapacity
              totalCapacity
            }
          }"
        
        $variables = "{
            `"showOrgColumn`": true,
            `"sortBy`": `"ClusterName`",
            `"sortOrder`": `"ASC`",
            `"filter`": {
              `"id`": [],
              `"name`": [
                `"`"
              ],
              `"type`": [],
              `"orgId`": []
            }
          }"
        
        
        $JSON_BODY = @{
            "variables" = $variables
            "query" = $query
        }
        $JSON_BODY = $JSON_BODY | ConvertTo-Json
        $clusterInfo = Invoke-WebRequest -Uri $POLARIS_URL -Method POST -Headers $headers -Body $JSON_BODY
        $clusterInfo = (((($clusterInfo.content | ConvertFrom-Json).data).clusterConnection).edges).node | where-object{$_.productType -ne "DATOS"}
        $clusterList = $clusterInfo.id | ConvertTo-Json
    }
    catch{
        Write-Error("Error $($_)")
    }
    End{
        Write-Output $clusterList
    }
}
function Get-ProtectionTaskDetails{
    
    Try{
        #Set Timeframe to scan based on $DaysToReport
        $InFormat = "yyyy-MM-ddTHH:mm:ss.fffZ"
        $currentDate = Get-Date -Format $InFormat 
        $startDate = ($currentDate | Get-Date).AddDays("-" + $daysToReport) | Get-Date -Format $InFormat
        $protectionTaskDetailsData = @()

        <#
        Can add
            "slaDomain": {
              "id": [
               `"${slaList}`""
              ]

        to the variables section if filtering based on SLA is desired

        #>
        $variables = "{
            `"first`": 200,
            `"filter`": {
              `"time_gt`": `"${startDate}`",
              `"time_lt`": `"${currentDate}`",
              `"clusterUuid`": ${clusterList},
              `"taskCategory`": [
                `"Protection`"
              ],
              `"taskType`": [
              `"Backup`"
            ],
              `"orgId`": []
            },
            `"sortBy`": `"EndTime`",
            `"sortOrder`": `"DESC`"
          }"
          $query = "query ProtectionTaskDetailTableQuery(`$first: Int!, `$after: String, `$filter: TaskDetailFilterInput, `$sortBy: TaskDetailSortByEnum, `$sortOrder: SortOrder) {
            taskDetailConnection(first: `$first, after: `$after, filter: `$filter, sortBy: `$sortBy, sortOrder: `$sortOrder) {
              edges {
                cursor
                node {
                  id
                  clusterUuid
                  clusterName
                  taskType
                  status
                  objectName
                  objectType
                  location
                  clusterLocation
                  slaDomainName
                  replicationSource
                  replicationTarget
                  archivalTarget
                  directArchive
                  failureReason
                  snapshotConsistency
                  protectedVolume
                  startTime
                  endTime
                  duration
                  dataTransferred
                  totalFilesTransferred
                  physicalBytes
                  logicalBytes
                  dedupRatio
                  logicalDedupRatio
                  dataReduction
                  logicalDataReduction
                  orgId
                  orgName
                }
              }
              pageInfo {
                endCursor
                hasNextPage
              }
            }
          }"
        $JSON_BODY = @{
            "variables" = $variables
            "query" = $query
        }
        $JSON_BODY = $JSON_BODY | ConvertTo-Json
        $result = Invoke-WebRequest -Uri $POLARIS_URL -Method POST -Headers $headers -Body $JSON_BODY
        $protectionTaskDetailsData += ((((($result.content) | ConvertFrom-Json).data).taskDetailConnection).edges).node

        while (((((($result.content) | ConvertFrom-Json).data).taskDetailConnection).pageinfo).hasNextPage -eq $true){
            $endCursor = ((((($result.content) | ConvertFrom-Json).data).taskDetailConnection).pageinfo).endCursor
            Write-Host ("Looking at End Cursor " + $endCursor)
            $variables = "{
                `"first`": 200,
                `"filter`": {
                    `"time_gt`": `"${startDate}`",
                    `"time_lt`": `"${currentDate}`",
                    `"clusterUuid`": ${clusterList},
                  `"taskCategory`": [
                    `"Protection`"
                  ],
                  `"taskType`": [
                    `"Backup`"
                  ],
                  `"orgId`": []
                },
                `"sortBy`": `"EndTime`",
                `"sortOrder`": `"DESC`",
                `"after`": `"${endCursor}`"
              }"
            $JSON_BODY = @{
                "variables" = $variables
                "query" = $query
            }
            $JSON_BODY = $JSON_BODY | ConvertTo-Json
            $result = Invoke-WebRequest -Uri $POLARIS_URL -Method POST -Headers $headers -Body $JSON_BODY
            $protectionTaskDetailsData += ((((($result.content) | ConvertFrom-Json).data).taskDetailConnection).edges).node 
        }
    }

    Catch{
        Write-Error("Error $($_)")
    }
    End{
        Write-Output $protectionTaskDetailsData
    }
}
function get-info{

    # Test Query

    process {

        try {

          <#
          {
  "first": 50,
  "filter": {
    "cluster": {
      "id": [
        "3bc43be7-00ca-4ed8-ba13-cef249d337fa",
        "39b92c18-d897-4b55-a7f9-17ff178616d0"
      ]
    },
    "complianceStatus": [
      "IN_COMPLIANCE",
      "OUT_OF_COMPLIANCE",
      "NOT_AVAILABLE"
    ],
    "protectionStatus": [],
    "slaTimeRange": "SINCE_PROTECTION",
    "orgId": []
  },
  "sortBy": "Name",
  "sortOrder": "ASC"
}
          #>
          if(!($ClusterId)) {
            Write-Host "Gathering Compliance Info for all clusters"
            $variables = "{
              `"first`": 200,
              `"filter`": {
                `"complianceStatus`": [
                  `"IN_COMPLIANCE`",
                  `"OUT_OF_COMPLIANCE`",
                  `"NOT_AVAILABLE`"
                ],
                `"protectionStatus`": [],
                `"slaTimeRange`": `"PAST_7_DAYS`",
                `"orgId`": []
              },
              `"sortBy`": `"Name`",
              `"sortOrder`": `"ASC`"
            }"
          }
          if($ClusterId) {
            #$ClusterId = $clusterId -replace '/s', ''
            $ClusterId = $ClusterId.Split(",")
            $ClusterId = $ClusterId | ConvertTo-Json
            #Fix Multicluster
            #Also not populating HTML files
            Write-Host ("Gathering Compliance Info for clusters " + $clusterId)
            $variables = "{
              `"first`": 200,
              `"filter`": {
                `"cluster`": {
                  `"id`": $clusterId
                },
                `"complianceStatus`": [
                  `"IN_COMPLIANCE`",
                  `"OUT_OF_COMPLIANCE`",
                  `"NOT_AVAILABLE`"
                ],
                `"protectionStatus`": [],
                `"slaTimeRange`": `"PAST_7_DAYS`",
                `"orgId`": []
              },
              `"sortBy`": `"Name`",
              `"sortOrder`": `"ASC`"
            }"
          }
   

            $query = "query ComplianceTableQuery(`$first: Int!, `$filter: SnappableFilterInput, `$after: String, `$sortBy: SnappableSortByEnum, `$sortOrder: SortOrder) {
                snappableConnection(first: `$first, filter: `$filter, after: `$after, sortBy: `$sortBy, sortOrder: `$sortOrder) {
                  edges {
                    cursor
                    node {
                      id
                      name
                      cluster {
                        id
                        name
                        id
                      }
                      slaDomain {
                        id
                        name
                        ... on GlobalSlaReply {
                          isRetentionLockedSla
                        }
                        ... on ClusterSlaDomain {
                          isRetentionLockedSla
                        }
                      }
                      location
                      complianceStatus
                      localSnapshots
                      replicaSnapshots
                      archiveSnapshots
                      totalSnapshots
                      missedSnapshots
                      lastSnapshot
                      latestArchivalSnapshot
                      latestReplicationSnapshot
                      objectType
                      fid
                      localOnDemandSnapshots
                      localSlaSnapshots
                      archivalSnapshotLag
                      replicationSnapshotLag
                      archivalComplianceStatus
                      replicationComplianceStatus
                      awaitingFirstFull
                      pullTime
                      orgName
                    }
                  }
                  pageInfo {
                    endCursor
                    hasNextPage
                  }
                }
              }"
              $JSON_BODY = @{
                "variables" = $variables
                "query" = $query
            }
            $JSON_BODY = $JSON_BODY | ConvertTo-Json

            $snappableInfo = @()
            $info = Invoke-WebRequest -Uri $POLARIS_URL -Method POST -Headers $headers -Body $JSON_BODY
            $snappableInfo += (((($info.content |ConvertFrom-Json).data).snappableConnection).edges).node
            while ((((($info.content |ConvertFrom-Json).data).snappableConnection).pageInfo).hasNextPage -eq $true){
                $endCursor = (((($info.content |ConvertFrom-Json).data).snappableConnection).pageInfo).endCursor
                Write-Host ("Looking at End Cursor " + $endCursor)
                if(!($ClusterId)) {
                  $variables =  $variables = "{
                    `"first`": 200,
                    `"filter`": {
                      `"complianceStatus`": [
                        `"IN_COMPLIANCE`",
                        `"OUT_OF_COMPLIANCE`",
                        `"NOT_AVAILABLE`"
                      ],
                      `"protectionStatus`": [],
                      `"slaTimeRange`": `"PAST_7_DAYS`",
                      `"orgId`": []
                    },
                    `"sortBy`": `"Name`",
                    `"sortOrder`": `"ASC`",
                    `"after`": `"${endCursor}`"
                  }"
                }
                if($ClusterId) {
                  $variables =  $variables = "{
                    `"first`": 200,
                    `"filter`": {
                      `"cluster`": {
                        `"id`": $clusterId
                      },
                      `"complianceStatus`": [
                        `"IN_COMPLIANCE`",
                        `"OUT_OF_COMPLIANCE`",
                        `"NOT_AVAILABLE`"
                      ],
                      `"protectionStatus`": [],
                      `"slaTimeRange`": `"PAST_7_DAYS`",
                      `"orgId`": []
                    },
                    `"sortBy`": `"Name`",
                    `"sortOrder`": `"ASC`",
                    `"after`": `"${endCursor}`"
                  }"
                }

                $JSON_BODY = @{
                    "variables" = $variables
                    "query" = $query
                }
                $JSON_BODY = $JSON_BODY | ConvertTo-Json
                $info = Invoke-WebRequest -Uri $POLARIS_URL -Method POST -Headers $headers -Body $JSON_BODY
                $snappableInfo += (((($info.content |ConvertFrom-Json).data).snappableConnection).edges).node
            }

        }

        Catch{

            Write-Error("Error $($_)")

        }

    }

    End {

        Write-Output $snappableInfo

    }

}
function get-SnapshotInfo{
    [CmdletBinding()]

    param (
        [parameter(Mandatory=$true)]
        [string]$snappableId
        #snappableId = FID, not ID
    )
    process {
        try{
            $snappableInfo = @()
            $variables = "{
                `"snappableId`": `"${snappableId}`",
                `"first`": 50,
                `"sortBy`": `"CREATION_TIME`",
                `"sortOrder`": `"DESC`",
                `"snapshotFilter`": [
                  {
                    `"field`": `"SNAPSHOT_TYPE`",
                    `"typeFilters`": []
                  },
                  {
                    `"field`": `"IS_LEGALLY_HELD`",
                    `"text`": `"false`"
                  }
                ],
                `"timeRange`": {
                    `"start`": `"${startDate}`",
                    `"end`": `"${currentDate}`"
                  }
              }"

            $query = "query SnapshotsListSingleQuery(`$snappableId: String!, `$first: Int, `$after: String, `$snapshotFilter: [SnapshotQueryFilterInput!], `$sortBy: SnapshotQuerySortByField, `$sortOrder: SortOrder, `$timeRange: TimeRangeInput) {
                snapshotsListConnection: snapshotOfASnappableConnection(workloadId: `$snappableId, first: `$first, after: `$after, snapshotFilter: `$snapshotFilter, sortBy: `$sortBy, sortOrder: `$sortOrder, timeRange: `$timeRange) {
                  edges {
                    cursor
                    node {
                      ...CdmSnapshotLatestUserNotesFragment
                      id
                      date
                      expirationDate
                      isOnDemandSnapshot
                      ... on CdmSnapshot {
                        cdmVersion
                        isRetentionLocked
                        isDownloadedSnapshot
                        cluster {
                          id
                          name
                          version
                          status
                          timezone
                        }
                        pendingSnapshotDeletion {
                          id: snapshotFid
                          status
                        }
                        slaDomain {
                          ...EffectiveSlaDomainFragment
                        }
                        pendingSla {
                          ...SLADomainFragment
                        }
                        snapshotRetentionInfo {
                          isCustomRetentionApplied
                          archivalInfos {
                            name
                            isExpirationDateCalculated
                            expirationTime
                            locationId
                          }
                          localInfo {
                            name
                            isExpirationDateCalculated
                            expirationTime
                          }
                          replicationInfos {
                            name
                            isExpirationDateCalculated
                            expirationTime
                            locationId
                            isExpirationInformationUnavailable
                          }
                        }
                        sapHanaAppMetadata {
                          backupId
                          backupPrefix
                          snapshotType
                          files {
                            backupFileSizeInBytes
                          }
                        }
                        legalHoldInfo {
                          shouldHoldInPlace
                        }
                      }
                      ... on PolarisSnapshot {
                        isDeletedFromSource
                        isDownloadedSnapshot
                        isReplica
                        isArchivalCopy
                        slaDomain {
                          name
                          ... on ClusterSlaDomain {
                            fid
                            cluster {
                              id
                              name
                            }
                          }
                          ... on GlobalSlaReply {
                            id
                          }
                        }
                      }
                    }
                  }
                  pageInfo {
                    endCursor
                    hasNextPage
                  }
                }
              }

              fragment EffectiveSlaDomainFragment on SlaDomain {
                id
                name
                ... on GlobalSlaReply {
                  isRetentionLockedSla
                }
                ... on ClusterSlaDomain {
                  fid
                  cluster {
                    id
                    name
                  }
                  isRetentionLockedSla
                }
              }

              fragment SLADomainFragment on SlaDomain {
                id
                name
                ... on ClusterSlaDomain {
                  fid
                  cluster {
                    id
                    name
                  }
                }
              }

              fragment CdmSnapshotLatestUserNotesFragment on CdmSnapshot {
                latestUserNote {
                  time
                  userName
                  userNote
                }
              }"
              $JSON_BODY = @{
                "variables" = $variables
                "query" = $query
            }
            $JSON_BODY = $JSON_BODY | ConvertTo-Json
            $result = Invoke-WebRequest -Uri $POLARIS_URL -Method POST -Headers $headers -Body $JSON_BODY
            $snappableInfo += (((($result.content | ConvertFrom-Json).data).snapshotsListConnection).edges).node

            while ((((($result.content | ConvertFrom-Json).data).snapshotsListConnection).pageInfo).hasNextPage -eq $true){
                $endCursor = ((((($result.content) | ConvertFrom-Json).data).taskDetailConnection).pageinfo).endCursor
                Write-Host ("Looking at End Cursor " + $endCursor)
                $variables = "{
                    `"first`": 50,
                    `"filter`": {
                        `"time_gt`": `"${startDate}`",
                        `"time_lt`": `"${currentDate}`",
                        `"clusterUuid`": ${clusterList},
                      `"taskCategory`": [
                        `"Protection`"
                      ],
                      `"taskType`": [
                        `"Backup`"
                      ],
                      `"orgId`": []
                    },
                    `"sortBy`": `"EndTime`",
                    `"sortOrder`": `"DESC`",
                    `"after`": `"${endCursor}`"
                  }"
                  "{
                    `"snappableId`": `"${snappableId}`",
                    `"first`": 50,
                    `"sortBy`": `"CREATION_TIME`",
                    `"sortOrder`": `"DESC`",
                    `"snapshotFilter`": [
                      {
                        `"field`": `"SNAPSHOT_TYPE`",
                        `"typeFilters`": []
                      },
                      {
                        `"field`": `"IS_LEGALLY_HELD`",
                        `"text`": `"false`"
                      }
                    ],
                    `"timeRange`": {
                        `"start`": `"${startDate}`",
                        `"end`": `"${currentDate}`"
                      },
                    `"after`": `"${endCursor}`"
                  }"
                $JSON_BODY = @{
                    "variables" = $variables
                    "query" = $query
                }
                $JSON_BODY = $JSON_BODY | ConvertTo-Json
                $result = Invoke-WebRequest -Uri $POLARIS_URL -Method POST -Headers $headers -Body $JSON_BODY
                $snappableInfo += (((($result.content | ConvertFrom-Json).data).snapshotsListConnection).edges).node 
            }

        }

        Catch{
            Write-Error("Error $($_)")
        }
    }
    End{
        Write-Output $snappableInfo
    }

}
Function Get-DateRange{ 
    #Function taken from https://thesurlyadmin.com/2014/07/25/quick-script-date-ranges/  
    [CmdletBinding()]
    Param (
        [datetime]$Start = (Get-Date),
        [datetime]$End = (Get-Date)
    )
    
    ForEach ($Num in (0..((New-TimeSpan –Start $Start –End $End).Days)))
    {   $Start.AddDays($Num)
    }
}

#Set Timeframe to scan based on $DaysToReport
$InFormat = "yyyy-MM-ddTHH:mm:ss.fffZ"
$currentDate = Get-Date -Format $InFormat 
$startDate = ($currentDate | Get-Date).AddDays("-" + $daysToReport) | Get-Date -Format $InFormat

#$daysToReport = 7
$polSession = connect-polaris
$rubtok = $polSession.access_token
$headers = @{
    'Content-Type'  = 'application/json';
    'Accept'        = 'application/json';
    'Authorization' = $('Bearer ' + $rubtok);
}
$Polaris_URL = ($serviceAccountObj.access_token_uri).replace("client_token", "graphql")
$logoutUrl = ($serviceAccountObj.access_token_uri).replace("client_token", "session")

$R2 = get-info

$R2Count = $R2 | Measure-Object | Select-Object -ExpandProperty Count
$R2ClusterCount = ($R2.cluster).id | Sort-Object -Unique |Measure-Object | Select-Object -ExpandProperty Count
$R2SLACount = $R2 | Select-Object SLAID -Unique | Measure-Object | Select-Object -ExpandProperty Count

# Totals
$TotalBackups = $R2 | Select-Object -ExpandProperty totalSnapshots | Measure-Object -Sum | Select-Object -ExpandProperty Sum

$TotalStrikes = $R2 | Select-Object -ExpandProperty missedSnapshots | Measure-Object -Sum | Select-Object -ExpandProperty Sum

$SummaryInfo = New-Object PSobject
$SummaryInfo | Add-Member -NotePropertyName "ObjectCount" -NotePropertyValue $R2Count
$SummaryInfo | Add-Member -NotePropertyName "ClusterCount" -NotePropertyValue $R2ClusterCount
$SummaryInfo | Add-Member -NotePropertyName "SLACount" -NotePropertyValue $R2SLACount
$SummaryInfo | Add-Member -NotePropertyName "TotalBackupsCount" -NotePropertyValue $TotalBackups
$SummaryInfo | Add-Member -NotePropertyName "TotalMissedBackupCount" -NotePropertyValue $TotalStrikes

# Averages

#$ObjectAverageHoursSince = $ObjectCompliance | Select -ExpandProperty HoursSince | Measure -Average | Select -ExpandProperty Average

#$ObjectAverageHoursSince = [Math]::Round($ObjectAverageHoursSince, 2)

# Objects

#Get Range of Dates Specified and setup table for html function later. 
$dateArray = Get-DateRange $startDate $currentDate
$dateReportTemplate = @()
ForEach($day in $dateArray){
    $formatedDate = $day.ToString("yyyy-MM-dd")
    $dateReportTemplate += $formatedDate
}

$dateFormattedReportTemplate = New-Object PSobject
#$dateFormattedReportTemplate | Add-Member -NotePropertyName "ObjectName" -NotePropertyValue ""
foreach($date in $dateReportTemplate){$dateFormattedReportTemplate | Add-Member -NotePropertyName $date -NotePropertyValue 1}

#Add in the DateRangeTemplate to Objects
ForEach($object in $R2){
    $object | Add-Member -NotePropertyName "AvailableBackupRange" -NotePropertyValue $dateFormattedReportTemplate
}

$ObjectsWithStrikes = $R2 | Where-Object {$_.missedSnapshots -gt 0} | Measure-Object | Select-Object -ExpandProperty Count
$objectsWithStrikesInfo = $R2 | Where-Object {$_.missedSnapshots -gt 0}
#$objectsWithoutStrikesInfo = $R2 | Where-Object {$_.missedSnapshots -eq 0}
$ObjectsWithoutStrikes = $R2 | Where-Object {$_.missedSnapshots -eq 0} | Measure-Object | Select-Object -ExpandProperty Count

$SummaryInfo | Add-Member -NotePropertyName "OutOfComplianceObjects" -NotePropertyValue $ObjectsWithStrikes
$SummaryInfo | Add-Member -NotePropertyName "InComplianceObjects" -NotePropertyValue $ObjectsWithoutStrikes

#Map the Missed Backups to the dateRangeTemplate
$ObjectStrikeSnapInfo = @()
ForEach($object in $R2){
    if($object.missedSnapshots -gt 0){
        Write-Host ($object.name + " is out of compliance. Gathering Snapshot Information.")
        $objectInfo = Get-SnapshotInfo $object.fid
        $snapshotList = @()
        forEach($snapshot in $objectInfo.date){
            $formatdate = $snapshot.ToString("yyyy-MM-dd")
            $snapshotList += $formatdate
        }
        $MissedBackups = (Compare-Object -ReferenceObject $dateReportTemplate -DifferenceObject $snapshotList).inputObject
        $BackupList = New-Object PSobject
        $BackupList | Add-Member -NotePropertyName "ObjectName"  -NotePropertyValue $object.name
        foreach($date in $dateReportTemplate){
            if($MissedBackups -contains $date){
                $BackupList | Add-Member -NotePropertyName $date -NotePropertyValue 0
            }
            else{
                $BackupList | Add-Member -NotePropertyName $date -NotePropertyValue 1
            }
        }
    }
    else{
        $BackupList = New-Object PSobject
        $BackupList | Add-Member -NotePropertyName "ObjectName"  -NotePropertyValue $object.name
        foreach($date in $dateReportTemplate){
            $BackupList | Add-Member -NotePropertyName $date -NotePropertyValue 1
        }
    }
    $object.AvailableBackupRange = $BackupList
    $ObjectStrikeSnapInfo += $object

}
#Swap over from $R2 to $ObjectStrikeSnapInfo

#Establish HTML Header information
$HtmlHead = '<style>
    body {
        background-color: white;
        font-family:      "Calibri";
    }

    table {
        border-width:     1px;
        border-style:     solid;
        border-color:     black;
        border-collapse:  collapse;
        width:            100%;
        margin:           50px;
    }

    th {
        border-width:     1px;
        padding:          5px;
        border-style:     solid;
        border-color:     black;
        background-color: #98C6F3;
    }

    td {
        border-width:     1px;
        padding:          5px;
        border-style:     solid;
        border-color:     black;
        background-color: White;
    }

    tr {
        text-align:       left;
    }
</style>'

#Get Color coordination for backup report
$HTMLData = ($ObjectStrikeSnapInfo).AvailableBackupRange |ConvertTo-Html -Head $HtmlHead | ForEach-Object {
  $PSItem -replace "<td>0</td>", "<td style='background-color:#FF8080'>No Backup</td>"
}
$FinishedData = $HTMLData | ForEach-Object{
  $PSItem -replace "<td>1</td>", "<td style='background-color:#008000'>Backup Available</td>"
}
$HTMLSummary = $SummaryInfo |ConvertTo-Html -Head $HtmlHead
$completedReport = $HTMLSummary + $FinishedData
#Wait-Debugger
Write-Host ("Writing report file to "  + $Output_directory + "/ChristmasTreeReport-" +$mdate + ".html")
$completedReport | Out-File ($Output_directory + "/ChristmasTreeReport-" +$mdate + ".html")
disconnect-polaris