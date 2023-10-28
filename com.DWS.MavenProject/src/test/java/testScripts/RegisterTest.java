package testScripts;

import java.io.IOException;

import org.apache.poi.EncryptedDocumentException;
import org.openqa.selenium.By;
import org.testng.annotations.DataProvider;
import org.testng.annotations.Listeners;
import org.testng.annotations.Test;

import genericLibrary.BaseTest;
import genericLibrary.ReadExcel;
@Listeners(genericLibrary.ListenerImplementation.class)
public class RegisterTest extends BaseTest{
	@Test(dataProvider = "registerData")
	public void registerTest(String gender, String firstName, String lastName, String email, String password) {
		  
		driver.findElement(By.className("ico-register")).click();
		  if(gender.equalsIgnoreCase("male")) {
		  driver.findElement(By.xpath("//input[@value='M']")).click();
		  }else if(gender.equalsIgnoreCase("female")) {
			  driver.findElement(By.xpath("//input[@value='F']")).click();
		  }
		  driver.findElement(By.id("FirstName")).sendKeys(firstName);
		  driver.findElement(By.id("LastName")).sendKeys(lastName);
		  driver.findElement(By.id("Email")).sendKeys(email);
		  driver.findElement(By.id("Password")).sendKeys(password);
		  driver.findElement(By.id("ConfirmPassword")).sendKeys(password);
		  driver.findElement(By.id("register-button")).click(); 
	}	
	@DataProvider(name= "registerData")
	public Object[][] registerData() throws EncryptedDocumentException, IOException {
		return ReadExcel.multipleRead("Register");
	}
}
