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
public class ShoppingCartTest extends BaseTest {
	@Test(dataProvider = "loginData")
	public void shoppingCartTest(String email, String password) {
		driver.findElement(By.className("ico-login")).click();
		driver.findElement(By.id("Email")).sendKeys(email);
		driver.findElement(By.id("Password")).sendKeys(password);
		driver.findElement(By.xpath("//input[@value='Log in']")).click();
		driver.findElement(By.partialLinkText("BOOKS")).click();
		driver.findElement(By.xpath("(//a[text()='Computing and Internet'])[2]/../..//input")).click();
		driver.findElement(By.partialLinkText("shopping cart")).click();
		driver.findElement(By.id("checkout")).click();	
	}
	@DataProvider(name= "loginData")
	public Object[][] loginData() throws EncryptedDocumentException, IOException {
		return ReadExcel.multipleRead("Login");
	}
}
