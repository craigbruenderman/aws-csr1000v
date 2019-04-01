from __future__ import print_function
from uuid import uuid4
import os
import velocloud
from velocloud.rest import ApiException
# If SSL verification disabled (e.g. in a development environment)
import urllib3
urllib3.disable_warnings()
velocloud.configuration.verify_ssl=False

client = velocloud.ApiClient(host="vco160-usca1.velocloud.net")
client.authenticate(os.environ.get('CORP_EMAIL'), os.environ.get('VCO160_PASSWORD'), operator=False)
api = velocloud.AllApi(client)

UNIQ = str(uuid4())
enterpriseId = 458

print("### GETTING ENTERPRISE CONFIGURATIONS ###")
params = { "enterpriseId": enterpriseId }
try:
    res = api.enterpriseGetEnterpriseConfigurations(params)
    print(res)
except ApiException as e:
    print(e)

profileId = res[1].id

edgeName = "AWS-%s" % UNIQ
print("### PROVISIONING EDGE ###")
params = { "enterpriseId": enterpriseId,
           "name": edgeName,
           "description": "A test Edge generated with the VeloCloud Python SDK",
           "modelNumber": "virtual",
           "configurationId": profileId }
try:
    res = api.edgeEdgeProvision(params)
    print(res)
except ApiException as e:
    print(e)
