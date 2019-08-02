/**
 * Created by Vuk Djukic - Anablock 
 */
public with sharing class onb_ApplicationFormController extends onb_BaseLightningController {
    public static string getSubmittedProductName;
    @AuraEnabled
    public static Map<String,Object> make(Map<String,Object> parameters) {
        Map<String,Object> result = new Map<String,Object>();
        try {
            String action = (String)parameters.get('action');
            Map<Object,Object> input =(Map<Object,Object>)parameters.get('input');
            Map<String,Object> output = new Map<String,Object>();
            if (action == 'init') {
                output.putAll(init(input));
            }
            else if (action == 'save') {
                output.putAll(save(input));
            }
            else if (action == 'products') {
                output.putAll(products(input));
            }
            result.put('data', output);
        }
        catch(Exception e) {
            result.put('error', (e instanceof DmlException) ? e.getDmlMessage(0) : e.getMessage());
            result.put('stack', e.getStackTraceString());
        }
        return result;
    }

    private static Map<String,Object> init(Map<Object,Object> parameters) {
        Id applicationId = (Id)parameters.get('application');
        String pageString = String.valueOf(parameters.get('page'));
        Decimal pageNumber = String.isEmpty(pageString) ? null : Decimal.valueOf(pageString);
        onb_Onboarding_Application__c app;
        if (applicationId != null) {
            app = new onb_Onboarding_Application__c(Id = applicationId);
        }
        else {
            User user = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId()];
            List<onb_Onboarding_Application__c> apps = [
                SELECT Id FROM onb_Onboarding_Application__c
                WHERE Onboarding_Account__c = :user.AccountId AND Status__c IN ('New','In Progress')
                ORDER BY CreatedDate DESC NULLS LAST
                LIMIT 1
            ];
            app = apps.isEmpty() ? null : apps[0];
        }

        onb_ApplicationFormRulesEngine.OnboardingApplicationForm result;
        if (app == null) {
            result = new onb_ApplicationFormRulesEngine.OnboardingApplicationForm();
        }
        else {
            result = onb_ApplicationFormRulesEngine.getInstance()
                                                    .loadRules(pageNumber)
                                                    .process(app);
        }

        return new Map<String,Object> {
            'data' => result
        };
    }

    private static Map<String,Object> save(Map<Object,Object> parameters) {
        onb_Onboarding_Application__c app = (onb_Onboarding_Application__c)JSON.deserialize(
            JSON.serialize(parameters.get('record')),
            onb_Onboarding_Application__c.class
        );

        FieldCleaner fc = new FieldCleaner(app.Id, (Boolean)parameters.get('cleanup') != true);

        upsert app;

        fc.blankout();

        return new Map<String,Object>();
    }

    private static Map<String,Object> products(Map<Object,Object> parameters) {
        onb_Onboarding_Application__c app = (onb_Onboarding_Application__c)JSON.deserialize(
            JSON.serialize(parameters.get('record')),
            onb_Onboarding_Application__c.class
        );
        List<String> products = (List<String>)JSON.deserialize(
            JSON.serialize(parameters.get('products')),
            List<String>.class
        );
        String condition = (String)parameters.get('condition');

        FieldCleaner fc = new FieldCleaner(app.Id, (Boolean)parameters.get('cleanup') != true);

        onb_ApplicationFormRulesEngine.Field productField = new onb_ApplicationFormRulesEngine.Field();
        productField.saveProducts(app, products, condition);

        fc.blankout();

        return new Map<String,Object>();
    }

    public class FieldCleaner {

        private Set<String> initiallyUsedFields;
        private Id applicationId;
        private Boolean bypass;

        public FieldCleaner(Id a, Boolean b) {
            this.applicationId = a;
            this.bypass = b == true;
            this.initiallyUsedFields = this.bypass ? new Set<String>() : this.calculateUsedFields();
        }

        public void blankout() {
            if (this.bypass) return;

            this.initiallyUsedFields.removeAll(this.calculateUsedFields());

            if (this.initiallyUsedFields.size() > 0) {
                onb_Onboarding_Application__c cleanupApp = new onb_Onboarding_Application__c(Id = this.applicationId);
                for (String cleanupField : this.initiallyUsedFields) {
                    cleanupApp.put(cleanupField, null);
                }
                update cleanupApp;
            }
        }

        private Set<String> calculateUsedFields() {
            Set<String> result = new Set<String>();
            onb_ApplicationFormRulesEngine.OnboardingApplicationForm form = onb_ApplicationFormRulesEngine.getInstance()
                                            .loadRules(null)
                                            .process(new onb_Onboarding_Application__c(Id = this.applicationId), true);
    
            for (onb_ApplicationFormRulesEngine.Field f : form.fields) {
                if (f.Type == 'Owner Form' || String.isBlank(f.APIName) || f.CbType == 'HTML') continue;
                result.add(f.APIName);
            }
    
            return result;
        }

    }

    /* 
     * unsubmitted - returns all applications which are visible to the calling user and have
     *               an unsubmitted status
     */
    
    public class Unsubmitted {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String legalEntityName;
        @AuraEnabled public String status;
        @AuraEnabled public Long createdDate;
        @AuraEnabled public List<onb_Onboarding_Application_Product__c> productList;
        @AuraEnabled public String productNameList = '';

        Unsubmitted(String id, String name, String status, Datetime createdDate, List<onb_Onboarding_Application_Product__c> productList, String legalEntityName) {
            this.id = id;
            this.name = name;
            this.status = status;
            this.createdDate = createdDate != NULL ? createdDate.getTime(): 0;
            for (onb_Onboarding_Application_Product__c productAppliedFor : productList) {
                productNameList += productAppliedFor.Name + ', ';
            }
            this.productNameList = productNameList.removeEnd(', ');
            this.legalEntityName = legalEntityName;
        }
    }

    @AuraEnabled
    public static unsubmitted[] unsubmitted() {

        Unsubmitted[] us = new list<unsubmitted>();

        try {
            for (onb_Onboarding_Application__c a : [
                SELECT Id, Name, Legal_Name__c, Status__c, CreatedDate, Application_Started_Date__c , (SELECT Name FROM Onboarding_Application_Products__r ORDER BY Name ASC)
                  FROM onb_Onboarding_Application__c
                 WHERE Status__c = 'New' OR Status__c = 'In Progress'
                 ORDER BY CreatedDate])
            {
                us.add(new Unsubmitted(a.Id, a.Name, a.Status__c, a.Application_Started_Date__c, a.Onboarding_Application_Products__r, a.Legal_Name__c));
            }

        } catch (Exception e) {
            System.debug(e.getMessage());
            return null;
        }

        return us;
    }

    /* 
     * submitted - returns all applications which are visible to the calling user and have
     *             submitted or post submitted status
     */
    public class Submitted {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String legalEntityName;
        @AuraEnabled public String status;
        @AuraEnabled public Long createdDate;
        @AuraEnabled public Long submittedDate;
        @AuraEnabled public List<onb_Onboarding_Application_Product__c> productList;
        @AuraEnabled public String productNameList = '';

        Submitted(String id, String name, String status, Datetime createdDate, Datetime submittedDate, List<onb_Onboarding_Application_Product__c> productList, String legalEntityName) {
            this.id = id;
            this.name = name;
            this.status = status;
            this.createdDate = createdDate != NULL ? createdDate.getTime() : 0;
            this.submittedDate = submittedDate != null ? submittedDate.getTime() : null;
            for (onb_Onboarding_Application_Product__c productAppliedFor : productList) {
                productNameList += productAppliedFor.Name + ', ';
            }
            this.productNameList = productNameList.removeEnd(', ');
            getSubmittedProductName = this.productNameList;
        }
    }
    @AuraEnabled
    public static Submitted[] submitted() {

        Submitted[] s = new list<Submitted>();

        try {
            for (onb_Onboarding_Application__c a : [
                SELECT Id, Name, Status__c, CreatedDate, Application_Submitted_Date__c, Legal_Name__c, (SELECT Name FROM Onboarding_Application_Products__r ORDER BY Name ASC)
                  FROM onb_Onboarding_Application__c
                 WHERE Status__c != 'New' AND Status__c != 'In Progress'
                 ORDER BY CreatedDate])
            {
                s.add(new Submitted(a.Id, a.Name, a.Status__c, a.CreatedDate, a.Application_Submitted_Date__c, a.Onboarding_Application_Products__r, a.Legal_Name__c));
            }

        } catch (Exception e) {
            System.debug(e.getMessage());
            return null;
        }

        return s;

    }

    @AuraEnabled
    public static Submitted[] completed() {

        Submitted[] s = new list<Submitted>();

        try {
            for (onb_Onboarding_Application__c a : [
                SELECT Id, Name, Legal_Name__c, Status__c, CreatedDate, Internal_Review_Completed_Date__c, (SELECT Name FROM Onboarding_Application_Products__r ORDER BY Name ASC)
                FROM onb_Onboarding_Application__c
                WHERE Status__c = 'Approved' OR Status__c = 'Rejected' OR Status__c = 'Canceled'
                ORDER BY CreatedDate])
            {
                s.add(new Submitted(a.Id, a.Name, a.Status__c, a.CreatedDate, a.Internal_Review_Completed_Date__c, a.Onboarding_Application_Products__r, a.Legal_Name__c));
            }

        } catch (Exception e) {
            System.debug(e.getMessage());
            return null;
        }

        return s;

    }

    @AuraEnabled
    public static Submitted[] underReview() {

        Submitted[] s = new list<Submitted>();

        try {
            for (onb_Onboarding_Application__c a : [
                SELECT Id, Name, Legal_Name__c, Status__c, CreatedDate, Application_Submitted_Date__c, (SELECT Name FROM Onboarding_Application_Products__r ORDER BY Name ASC)
                FROM onb_Onboarding_Application__c
                WHERE Status__c = 'Submitted' OR Status__c = 'In Review' OR Status__c = 'Partial Approval'
                ORDER BY CreatedDate])
            {
                s.add(new Submitted(a.Id, a.Name, a.Status__c, a.CreatedDate, a.Application_Submitted_Date__c, a.Onboarding_Application_Products__r, a.Legal_Name__c));
            }

        } catch (Exception e) {
            System.debug(e.getMessage());
            return null;
        }

        return s;

    }

    @AuraEnabled
    public static void createNewApplication() {
        User uu = [SELECT Id, Name, ContactId, AccountId FROM User WHERE Id = :UserInfo.getUserId()];
        onb_Onboarding_Application__c newApp = new onb_Onboarding_Application__c(
            Name = 'Business Onboarding Application',
            Onboarding_Account__c = uu.AccountId,
            Applying_Contact__c = uu.ContactId,
            Is_Delta_Application__c = getApplicationInfo().isDelta == true
        );
        List<String> sourceFields = new List<String>();
        for (Schema.FieldSetMember field : SObjectType.Account.FieldSets.Additional_Application.getFields()) {
            sourceFields.add(field.getFieldPath());
        }
        Id currentUserAccountId = uu.AccountId;
        Account sourceAccount = Database.query(
            String.format(
                String.join(
                    new List<String> {
                        'SELECT {0}',
                        'FROM Account',
                        'WHERE Id = :currentUserAccountId'
                    },
                    ' '
                ),
                new List<String> {
                    String.join(sourceFields, ', ')
                }
            )
        );
        List<Schema.FieldSetMember> applicationFields = SObjectType.onb_Onboarding_Application__c.FieldSets.Additional_Application.getFields();
        for (Integer i = 0; i < sourceFields.size(); i++) {
           try {
               newApp.put(
                   applicationFields[i].getFieldPath(),
                   sourceAccount.get(sourceFields[i])
               );
           }
           catch(Exception e) {}
        }
        insert newApp;
    }

    @AuraEnabled
    public static InfoWrapper getApplicationInfo_V2() {
        Unsubmitted[] draft = unsubmitted();
        Submitted[] underReview = underReview();
        Submitted[] completed = completed();
        return new InfoWrapper(draft, underReview, completed);
    }

    @AuraEnabled
    public static Info getApplicationInfo() {
        return new Info();
    }

    public class InfoWrapper {
        @AuraEnabled public Info generalInfo;
        @AuraEnabled public Unsubmitted[] draft;
        @AuraEnabled public Submitted[] underReview;
        @AuraEnabled public Submitted[] completed;

        InfoWrapper(Unsubmitted[] draft, Submitted[] underReview, Submitted[] completed) {
            this.generalInfo = new Info();
            this.draft = draft;
            this.underReview = underReview;
            this.completed = completed;
        }
    }

    public without sharing class Info {
        @AuraEnabled public Boolean showContinueButton;
        @AuraEnabled public Boolean showCancelButton;
        @AuraEnabled public Boolean showNewAppButton;
        public List<AccountProduct__c> onboardedProduct;
        Public Integer onboardedCount;
        public Boolean checkPro = False; 
        public Boolean checkPrime= False; 
        public Boolean checkCustody = False;
        public Boolean isDelta = false;
        final Set<String> activeApplicationStatusValues = new Set<String> {'New', 'In Progress'};
        final Set<String> submittedApplicationStatusValues = new Set<String> {'Submitted', 'In Review'};
        @AuraEnabled public String legalEntityName;
        @AuraEnabled public String submitOrReviewStatus;
        @AuraEnabled public String submittedProduct = getSubmittedProductName;
        @AuraEnabled public string submittedDate;
        public List<String> allMonthList= new List<String>{'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};

        public Info() {
            User currentUser = [SELECT Id, AccountId FROM User WHERE Id = :UserInfo.getUserId()];

            this.showContinueButton = false;
            this.showCancelButton = false;
            this.showNewAppButton = false;

            onboardedProduct = [
                SELECT Product__r.Name FROM AccountProduct__c
                WHERE Account__c = :currentUser.AccountId
                    AND (Product__r.Name LIKE '%Prime%' OR Product__r.Name LIKE '%Pro%' OR Product__r.Name LIKE '%Custody%')
            ];
            onboardedCount = onboardedProduct.size();
            for(AccountProduct__c apc : onboardedProduct){
                if(String.ValueOf(apc.Product__r.Name).contains('Pro')){
                    checkPro = True;
                }else if(String.ValueOf(apc.Product__r.Name).contains('Prime')){
                    checkPrime = True;
                }else if(String.ValueOf(apc.Product__r.Name).contains('Custody')){
                    checkCustody = True;
                }
            }

            if ((checkPro || checkPrime) && checkCustody) {
                this.showNewAppButton = false;
            } else {
                this.showNewAppButton = true;
                this.isDelta = onboardedCount > 0;
            }  
            for (onb_Onboarding_Application__c oao : [
                SELECT Id,Status__c,Legal_Name__c,Application_Submitted_Date__c FROM onb_Onboarding_Application__c
                WHERE Onboarding_Account__c = :currentUser.AccountId
            ]) {
                if (activeApplicationStatusValues.contains(oao.Status__c)) {
                    this.showContinueButton = true;
                    this.showNewAppButton = false;
                }
                else if (submittedApplicationStatusValues.contains(oao.Status__c)) {
                    this.showCancelButton = true;
                    this.showNewAppButton = false;
                }
                this.legalEntityName = oao.Legal_Name__c;
                this.submitOrReviewStatus = oao.Status__c;
                if(oao.Application_Submitted_Date__c != null)
                    this.submittedDate =  allMonthList[oao.Application_Submitted_Date__c.month() - 1] +' '+ oao.Application_Submitted_Date__c.day()+' '+string.valueOf(oao.Application_Submitted_Date__c.year());
            
            }
        }
    }

    @AuraEnabled
    public static void cancelCurrentApplication() {
        List<onb_Onboarding_Application__c> onbAppToCancel = new List<onb_Onboarding_Application__c>();
        List<Case> casesToCancel = new List<Case>();
        User currentUser = [SELECT Id, AccountId FROM User WHERE Id = :UserInfo.getUserId()];
        onb_Onboarding_Application__c appToCancel = [SELECT Status__c, (SELECT Id, Status, Sub_Status__c FROM Cases__r WHERE Sub_Status__c != 'Client Canceled') FROM onb_Onboarding_Application__c WHERE Onboarding_Account__c = :currentUser.AccountId AND Status__c IN ('Submitted', 'In Review', 'In Progress') ORDER BY CreatedDate DESC NULLS LAST LIMIT 1];
        
        if(appToCancel != null) {
            appToCancel.Status__c = 'Canceled';
            onbAppToCancel.add(appToCancel);
            if(appToCancel.Cases__r != null) {
                for (Case cse : appToCancel.Cases__r) {
                    cse.Status = 'Closed';
                    cse.Sub_Status__c = 'Client Canceled';
                    casesToCancel.add(cse);
                }
            }
        }

        try {
            if(!onbAppToCancel.isEmpty()) {
                update onbAppToCancel;
            }
            if(!casesToCancel.isEmpty()) {
                update casesToCancel;
            }
        } catch (Exception e) {
            system.debug('Failed to cancel Application os Case: '+ e.getMessage() + ' : Line Number : ' + e.getLineNumber());
        }
    }

    @AuraEnabled
    public static User userInfo() {
        return onb_BaseLightningController.userInfo();
    }

    @AuraEnabled
    public static String baseUrl() {
        return URL.getSalesforceBaseUrl().toExternalForm();
    }
    
    // To capture Application_Started_Date__c only landing for the first time
    //SSCM1-2089 Stamp status to In Progress
    @AuraEnabled
    public static void appStartDate(String applicationEvent) {
        system.debug('applicationEvent> > ' + applicationEvent);
        List<onb_Onboarding_Application__c> onbAppStartIdList = new List<onb_Onboarding_Application__c>();
        User user = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId()];
        try{
        onb_Onboarding_Application__c apps = [
                    SELECT Id,Application_Started_Date__c,Status__c,Client_attests_all_answers_are_true__c,Application_Submitted_Date__c  FROM onb_Onboarding_Application__c
                    WHERE Onboarding_Account__c = :user.AccountId AND Status__c IN ('New', 'In Progress')
                    ORDER BY CreatedDate DESC NULLS LAST LIMIT 1];

            if(apps.Application_Started_Date__c == null && applicationEvent == 'stampstartdate'){
                apps.Application_Started_Date__c = DateTime.now();
                apps.Status__c=Label.onbApplicationStatusInProgress;
                onbAppStartIdList.add(apps);
            }
            if(apps.Status__c != Label.onbApplicationStatusSubmitted && applicationEvent == 'stampsubmitdate'){
                apps.Application_Submitted_Date__c = DateTime.now();
                apps.Status__c=Label.onbApplicationStatusSubmitted;
                apps.Client_attests_all_answers_are_true__c='Yes';
                onbAppStartIdList.add(apps);
                onb_ApplicationOwnerController.cleanupOwnerRecords(apps.Id);
            }
            update onbAppStartIdList;
        }
        catch(Exception e){
            system.debug('Failed to update or find Application: '+ e.getMessage()+ ' : Line Number : '+e.getLineNumber());
        }
    }

}