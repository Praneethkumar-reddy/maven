package testScripts;

import org.openqa.selenium.By;
import org.testng.Assert;
import org.testng.annotations.Test;

import genericLibrary.BaseTest;
import pomRepo.LoginPage;
import pomRepo.WelcomePage;

//packageName.className.class

public class LoginTest extends BaseTest {
	
	@Test(/* dataProvider = "loginData" */)
	public void loginTest(/* String email, String password */) {
		WelcomePage welcomePage=new WelcomePage(driver);
		welcomePage.clickLoginLink();
		
		LoginPage loginPage=new LoginPage(driver);
		loginPage.enterEmail("yogita");
		loginPage.passwordTextField.sendKeys("password");
		Assert.assertTrue(false);
		driver.findElement(By.xpath("//input[@value='Log in']")).click();
		action.moveToElement(null);
		
	}
	/*
	 * @DataProvider(name= "loginData") public Object[][] loginData() throws
	 * EncryptedDocumentException, IOException { return
	 * ReadExcel.multipleRead("Login"); }
	 */
}
