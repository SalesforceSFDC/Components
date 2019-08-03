public with sharing class ApplicationDocumentController{

	@AuraEnabled
	public static Map<String,Object> make(Map<String,Object> parameters) {
		Map<String,Object> result = new Map<String,Object>();
		try {
			String action = (String)parameters.get('action');
			Map<Object,Object> input =(Map<Object,Object>)parameters.get('input');
			Map<String,Object> output = new Map<String,Object>();
			if (action == 'save') {
				output.putAll(save(input));
			}
			else if (action == 'delete') {
				output.putAll(deleteDocument(input));
			}
			else if (action == 'refreshDocuments'){
				output.putAll(refreshDocuments(input));
			}
			result.put('data', output);
		}
		catch(Exception e) {
			result.put('error', (e instanceof DmlException) ? e.getDmlMessage(0) : e.getMessage());
			result.put('stack', e.getStackTraceString());
		}
		return result;
	}

	/**
	 * After file upload is finished, create ContentDocumentLink records between the uploaded documents and an Onboarding Application Document
	 * record, creating the OAD if one does not exist already.
	 *
	 * @param parameters
	 *
	 * @return
	 */
	private static Map<String,Object> save(Map<Object,Object> parameters) {


		List<Object> uploadedObjects = (List<Object>)parameters.get('uploadedFiles');
		List<Map<Object,Object>> uploadedFiles = new List<Map<Object,Object>>();

		for(Object obj: uploadedObjects){
			Map<Object,Object> currentFile = (Map<Object,Object>) obj;
			uploadedFiles.add(currentFile);
		}
		Id applicationDocumentId = (Id)parameters.get('applicationDocumentId');
		system.debug(uploadedFiles);
		system.debug(applicationDocumentId);

		List<ContentDocumentLink> contentDocumentLinksToInsert = new List<ContentDocumentLink>();
		List<Id> contentDocumentIds = new List<Id>();

		Id parentId = (Id)parameters.get('parentId');

		String documentType = (String)parameters.get('documentType');

		for(Map<Object,Object> currentFile: uploadedFiles){
			contentDocumentIds.add((Id)currentFile.get('documentId'));
		}
		system.debug(contentDocumentIds);


		if(applicationDocumentId == null) {
			onb_Onboarding_Application_Document__c appDoc = new onb_Onboarding_Application_Document__c(
					Name = (String)uploadedFiles[0].get('name'),
					Document_Type__c = documentType
			);
			if (parentId.getSObjectType().getDescribe() == SObjectType.onb_Onboarding_Application__c) {
				appDoc.onb_Onboarding_Application__c = parentId;
			} else {
				onb_Onboarding_Application_Owner__c oao = [SELECT onb_Onboarding_Application__c FROM onb_Onboarding_Application_Owner__c WHERE Id = :parentId];
				appDoc.onb_Onboarding_Application__c = oao.onb_Onboarding_Application__c;
				appDoc.Onboarding_Application_Owner__c = parentId;
			}
			insert appDoc;
			applicationDocumentId = appDoc.Id;
		}

		String returnFileId = '';
		for(ContentDocument cd: [SELECT Id, ParentId, LatestPublishedVersionId FROM ContentDocument WHERE Id in :contentDocumentIds]){
			ContentDocumentLink cdl = new ContentDocumentLink(
					ContentDocumentId = cd.Id,
					LinkedEntityId = applicationDocumentId,
					ShareType = 'I'
			);
			contentDocumentLinksToInsert.add(cdl);
			returnFileId = cd.LatestPublishedVersionId;
		}

		insert contentDocumentLinksToInsert;

		return new Map<String,Object> {
			'fileId' => returnFileId,
			'applicationDocumentId' => applicationDocumentId
		};
	}


	/**
	 * Delete the ContentDocument, and the related Onboarding Application Document record if there are no additional related documents after deletion.
	 *
	 * @param parameters
	 *
	 * @return
	 */
	private static Map<String,Object> deleteDocument(Map<Object,Object> parameters) {
		Id contentVersionId = (Id)parameters.get('id');

		String nextFileId = null;
		ContentVersion cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersionId];

		Set<Id> oadIds = new Set<Id>();
		for (ContentDocumentLink cdl : [SELECT LinkedEntityId FROM ContentDocumentLink WHERE ContentDocumentId = :cv.ContentDocumentId]) {
			oadIds.add(cdl.LinkedEntityId);
		}

		delete new ContentDocument(Id = cv.ContentDocumentId);

		List<onb_Onboarding_Application_Document__c> onboardingAppsToDelete = new List<onb_Onboarding_Application_Document__c>();

		//Delete the onboarding Application Document if the deletion of the content document results in no contentdocuments linked to the Application Document
		for(onb_Onboarding_Application_Document__c appDoc: [SELECT Id, (Select ContentDocument.LatestPublishedVersionId,ContentDocument.Title from ContentDocumentLinks) FROM onb_Onboarding_Application_Document__c WHERE Id IN :oadIds]){
			if(appDoc.ContentDocumentLinks.isEmpty()){
				onboardingAppsToDelete.add(appDoc);
			}else{
				nextFileId = appDoc.ContentDocumentLinks[0].ContentDocument.LatestPublishedVersionId;
			}
		}
		delete onboardingAppsToDelete;

		return new Map<String,Object>{'fileId' => nextFileId};
	}

	/**
	 * Refresh the list that stores sibling documents related to the same Onboarding Application Document record.
	 *
	 * @param parameters
	 *
	 * @return
	 */
	private static Map<String,Object> refreshDocuments(Map<Object,Object> parameters) {
		system.debug('refreshing list of documents');
		Id contentVersionId = (Id)parameters.get('id');
		system.debug('contentVersionId ' + contentVersionId);
		Map<String, Object> emptyList = new Map<String, Object>{ 'documents' => new List<DocumentWrapper>()};
		if(contentVersionId == null){
			return emptyList;
		}
		else {
			if([SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersionId].isEmpty()){
				system.debug('no contentVersion exists');
				return emptyList;
			}
			ContentVersion cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersionId];

			Set<Id> linkedEntityIds = new Set<Id>();
			for (ContentDocumentLink cdl : [SELECT LinkedEntityId FROM ContentDocumentLink WHERE ContentDocumentId = :cv.ContentDocumentId]) {
				linkedEntityIds.add(cdl.LinkedEntityId);
			}
			//filter for onboarding application documents only
			String applicationDocumentId = null;
			Set<Id> oadIds = new Set<Id>();
			for (onb_Onboarding_Application_Document__c onboardingApplicationDocument : [SELECT Id FROM onb_Onboarding_Application_Document__c WHERE Id in: linkedEntityIds]) {
				oadIds.add(onboardingApplicationDocument.Id);
				applicationDocumentId = onboardingApplicationDocument.Id;
			}
			system.debug('onboarding document Ids: ' + oadIds);

			List<DocumentWrapper> relatedDocumentWrappers = new List<DocumentWrapper>();
			//Get all files linked to the same onboarding application document
			for(ContentDocumentLink cdl: [SELECT ContentDocument.LatestPublishedVersionId, ContentDocument.Title FROM ContentDocumentLink WHERE LinkedEntityId in : oadIds]){
				relatedDocumentWrappers.add(new DocumentWrapper(cdl.ContentDocument.LatestPublishedVersionId, cdl.ContentDocument.Title));

			}
			system.debug('related documents : ' + relatedDocumentWrappers);
			system.debug(applicationDocumentId);
			return new Map<String, Object>{
					'documents' => relatedDocumentWrappers,
					'applicationDocumentId' => applicationDocumentId
			};
		}
	}

	public class DocumentWrapper{
		@AuraEnabled
		public Id fileId;
		@AuraEnabled
		public String fileName;

		public DocumentWrapper(String fileId, String fileName){
			this.fileId = fileId;
			this.fileName = fileName;
		}

	}


}