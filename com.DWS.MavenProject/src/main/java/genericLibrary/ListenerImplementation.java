package genericLibrary;

import org.testng.ITestContext;
import org.testng.ITestListener;
import org.testng.ITestResult;

public class ListenerImplementation  implements ITestListener {

	@Override
	public void onTestFailure(ITestResult result) {
		//UtilityMethods.getScreenshot(result.getName()); 
		System.out.println("Test failed");
	}
	
	@Override
	public void onStart(ITestContext context) {
		System.out.println("Test case execution started");
	}
	
	@Override
	public void onFinish(ITestContext context) {
		System.out.println("Test case execution finished");
	}
	
}
