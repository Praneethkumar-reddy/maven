package testScripts;

import org.openqa.selenium.By;
import org.testng.annotations.Test;

import genericLibrary.BaseTest;
import pomRepo.WelcomePage;

public class SwitchWindowTest extends BaseTest {
	
	@Test
	public void test() throws InterruptedException {
		String parentWindowHandle=driver.getWindowHandle();
		WelcomePage welcomePage=new WelcomePage(driver);
		welcomePage.clickTwitterLink();
		switchToParticularTitledWindow("Twitter");
		driver.findElement(By.xpath("//span[text()='Settings']")).click();
		Thread.sleep(3000);
		driver.switchTo().window(parentWindowHandle);
		driver.findElement(By.partialLinkText("BOOKS")).click();
	}

}
