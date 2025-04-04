/**
 * States and Countries cannot be created by deploying Address Settings.
 * This tool submits all states into the Setup screen using page scraping.
 *
 * Resolves:
 * https://success.salesforce.com/ideaView?id=08730000000l6DGAAY
 * https://salesforce.stackexchange.com/questions/20755/how-to-mass-populate-state-country-picklist-values
 * https://salesforce.stackexchange.com/questions/78377/how-to-write-address-settings-in-order-to-implement-country-picklists-via-metada
 */
public inherited sharing class StateCodes implements Database.Batchable<StateCodes.StateData>, Database.AllowsCallouts, HttpCalloutMock
{
    public List<StateData> stateCodes {get; set;}
    ApexPages.StandardController controller;
    private List<StateData> stateDataList;

    public class StateData {
        public String stateCode;
        public String stateName;
        public String integrationValue;
        
        public StateData(String stateCode, String stateName, String integrationValue) {
            this.stateCode = stateCode;
            this.stateName = stateName;
            this.integrationValue = integrationValue;
        }
    }

    public StateCodes(ApexPages.StandardController controller)
    {
        this.controller = controller;
        this.stateCodes = getStateDataList();
        this.stateDataList = getStateDataList();
    }

    public List<StateData> getStateDataList() {
        return new List<StateData>{
            new StateData('CN-110', 'Anhui', '110'),
            new StateData('CN-AH', 'Anhui', 'AH'),
            new StateData('CN-010', 'Beijing', '010'),
            new StateData('CN-BJ', 'Beijing', 'BJ'),
            new StateData('CN-320', 'Chong Qing', '320'),
            new StateData('CN-CQ', 'Chongqing', 'CQ'),
            new StateData('CN-150', 'Fujian', '150'),
            new StateData('CN-FJ', 'Fujian', 'FJ'),
            new StateData('CN-260', 'Gansu', '260'),
            new StateData('CN-GS', 'Gansu', 'GS'),
            new StateData('CN-190', 'Guangdong', '190'),
            new StateData('CN-GD', 'Guangdong', 'GD')
        };
    }

    public PageReference action()
    {
        if (this.controller.getId() != null)
        {
            this.controller.reset();
            return null;
        }
        else
        {
            List<AsyncApexJob> jobs = [SELECT Id FROM AsyncApexJob WHERE CompletedDate = null AND ApexClass.Name = 'StateCodes'];
            if (!jobs.isEmpty()) return new PageReference('/apex/StateCodes?id=' + jobs[0].Id);
            else return null;
        }
    }

    public PageReference startBatch()
    {
        try
        {
            Id jobId = run(stateDataList);
            
            PageReference redirect = new PageReference('/apex/StateCodes');
            redirect.getParameters().put('id', jobId);
            redirect.setRedirect(true);
            return redirect;
        }
        catch (Exception e)
        {
            ApexPages.addMessages(e);
            return null;
        }
    }

    public void abortBatch()
    {
        try
        {
            System.AbortJob(controller.getId());
            this.controller.reset();
        }
        catch (Exception e)
        {
            ApexPages.addMessages(e);
        }
    }

    static public Id run(List<StateData> stateDataList)
    {
        if (isRunning()) throw new AsyncException('Batch already running');
        StateCodes batch = new StateCodes();
        if (stateDataList != null) 
        {
            batch.stateDataList = stateDataList;
        }
        else 
        {
            batch.stateDataList = batch.getStateDataList(); 
        }
        return Database.executeBatch(batch, 1);
    }

    static Boolean isRunning()
    {
        return ![
            SELECT Id
            FROM AsyncApexJob
            WHERE CompletedDate = null
            AND ApexClass.Name = 'StateCodes'
        ].isEmpty();
    }

    @TestVisible StateCodes()
    {
        // use run() method
    }

    public Iterable<StateData> start(Database.BatchableContext context)
    {
        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setEndpoint(Url.getOrgDomainUrl().toExternalForm());
        if (!Test.isRunningTest()) new Http().send(request);
        
        return stateDataList;
    }

    public void execute(Database.BatchableContext context, List<StateData> stateDataList)
    {     
        // Fetch all existing state names
        Set<String> existingStateNames = new Set<String>();
        for (StateData stateData : stateDataList) {
            String stateName = stateData.stateName;
            existingStateNames.add(stateName);
        }
        Map<String, StateData> existingStates = new Map<String, StateData>();
        for (StateData stateData : stateDataList) {
            if (existingStates.containsKey(stateData.stateName)) {
                stateData.integrationValue = stateData.integrationValue;
            } else {
                stateData.integrationValue = stateData.stateName;
            }
            existingStates.put(stateData.stateName, stateData);
        }

        // Process the state data list
        for (StateData stateData : stateDataList)
        {
            String countryCode = stateData.stateCode.substringBefore('-');
            String stateCode = stateData.stateCode.substringAfter('-');
            String stateName = stateData.stateName;
            String integrationValue = stateData.integrationValue;
            
            try
            {
                newState(countryCode, stateCode, stateName, integrationValue);
            }
            catch (HandledException e)
            {
                System.debug('HandledException: ' + e.getMessage());
                continue;
            }
            catch (UnsupportedOperationException e)
            {
                System.debug('UnsupportedOperationException: ' + e.getMessage());
            }
            catch (Exception e)
            {
                System.debug('Unexpected Exception: ' + e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext context)
    {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setSaveAsActivity(false);
        email.setTargetObjectId(UserInfo.getUserId());
        email.setSubject('State Codes - batch completed');
        email.setPlainTextBody('See results in Documents and Apex Jobs page');
        Messaging.sendEmail(new List<Messaging.Email>{email});
    }

    static HttpResponse sendTwice(HttpRequest request)
    {
        request.setTimeout(60 * 1000);
        try
        {
            return new Http().send(request);
        }
        catch (CalloutException e)
        {
            if (Test.isRunningTest()) throw e; else return new Http().send(request);
        }
    }

    public void newState(String countryCode, String stateCode, String stateName, String integrationValue)
    {
        String orgUrl = Url.getOrgDomainUrl().toExternalForm();
        
        HttpRequest getRequest = new HttpRequest();
        getRequest.setMethod('GET');
        getRequest.setEndpoint(orgUrl + '/i18n/ConfigureNewState.apexp?countryIso=' + countryCode);
        getRequest.setHeader('Cookie', 'sid=' + UserInfo.getSessionId());
        
        if (Test.isRunningTest()) Test.setMock(HttpCalloutMock.class, this);
        HttpResponse getResponse = sendTwice(getRequest);
        
        String viewState = getResponse.getBody().substringBetween('com.salesforce.visualforce.ViewState" value="', '"');
        String viewStateMac = getResponse.getBody().substringBetween('com.salesforce.visualforce.ViewStateMAC" value="', '"');
        String viewStateCsrf = getResponse.getBody().substringBetween('com.salesforce.visualforce.ViewStateCSRF" value="', '"');
        String viewStateVersion = getResponse.getBody().substringBetween('com.salesforce.visualforce.ViewStateVersion" value="', '"');
        
        PageReference postdata = new PageReference('');
        Map<String,String> parameters = postdata.getParameters();
        
        parameters.put('configurenew:j_id1', 'configurenew:j_id1');
        parameters.put('configurenew:j_id1:blockNew:j_id43:addButton', 'Add');
        parameters.put('configurenew:j_id1:blockNew:j_id9:nameSectionItem:editName', stateName);
        parameters.put('configurenew:j_id1:blockNew:j_id9:codeSectionItem:editIsoCode', stateCode);
        parameters.put('configurenew:j_id1:blockNew:j_id9:intValSectionItem:editIntVal', integrationValue);
        
        parameters.put('com.salesforce.visualforce.ViewState', viewState);
        parameters.put('com.salesforce.visualforce.ViewStateVersion', viewStateVersion);
        parameters.put('com.salesforce.visualforce.ViewStateMAC', viewStateMac);
        parameters.put('com.salesforce.visualforce.ViewStateCSRF', viewStateCsrf);
        
        HttpRequest postRequest = new HttpRequest();
        postRequest.setMethod('POST');
        postRequest.setBody(postdata.getUrl().substringAfter('?'));
        postRequest.setEndpoint(orgUrl + '/i18n/ConfigureNewState.apexp');
        postRequest.setHeader('Cookie', 'sid=' + UserInfo.getSessionId());
        postRequest.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        
        if (Test.isRunningTest()) Test.setMock(HttpCalloutMock.class, this);
        HttpResponse postResponse = sendTwice(postRequest);
        
        if (postResponse.getBody().contains('<h4>Errors</h4>'))
        {
            String message = postResponse.getBody().substringBetween('<li style="padding-top:5px">', '</li>').trim();
            throw new HandledException(message);
        }
        
        if (postResponse.getBody().contains('<h4>Error:</h4>'))
        {
            String message = postResponse.getBody().substringBetween('<h4>Error:</h4></span>', '<').trim();
            throw new HandledException(message);
        }
        
        if (postResponse.getBody().contains('You are missing information'))
        {
            String message = 'Country does not exist: ' + countryCode;
            throw new HandledException(message);
        }
        
        if (!postResponse.getBody().contains('success=true'))
        {
            String message = 'Cannot find success redirect: ' + postResponse.getBody();
            throw new UnsupportedOperationException(message);
        }
    }

    public HttpResponse respond(HttpRequest request)
    {
        HttpResponse response = new HttpResponse();
        if (request.getMethod() == 'GET') response.setBody('<html></html>');
        if (request.getMethod() == 'POST') response.setBody('<a href="/?success=true">OK</a>');
        return response;
    }
}
