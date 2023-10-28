package genericLibrary;

import java.io.File;
import java.io.IOException;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Set;

import org.openqa.selenium.OutputType;
import org.openqa.selenium.TakesScreenshot;
import org.openqa.selenium.WebDriver;
import org.openqa.selenium.WebElement;
import org.openqa.selenium.interactions.Actions;
import org.openqa.selenium.io.FileHandler;
import org.openqa.selenium.support.ui.Select;
import org.openqa.selenium.support.ui.WebDriverWait;

public class UtilityMethods {
	
	public WebDriver driver;
	public Select select;
	public Actions action;
	public WebDriverWait wait;
	
	public void initObjects() {
		action=new Actions(driver);
		wait=new WebDriverWait(driver, Duration.ofSeconds(10));
		
	}

	
	public  void getScreenshot() {
		LocalDateTime dateTime=LocalDateTime.now();
		String dataStamp=dateTime.toString().replaceAll(":", "-");
		
		TakesScreenshot ts = (TakesScreenshot) driver;
		File temp = ts.getScreenshotAs(OutputType.FILE);
		File dest=new File("./Screenshots/"+dataStamp+".png");
		try {
			FileHandler.copy(temp, dest);
		} catch (IOException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		}	
	}
	
	public void selectOptionInDropDown(WebElement listbox, String option) {
		Select select = new Select(listbox);
		int counter = 0;
		try {
			int index = Integer.parseInt(option);
			select.selectByIndex(index);
			counter++;
		} catch (Exception e) {
			System.out.println("It is not a index");
		}
		if (counter == 0) {
			try {
				select.selectByVisibleText(option);
			} catch (Exception e) {
				select.selectByValue(option);
			}
		}
	}	
	public void switchToParticularTitledWindow(String title) throws InterruptedException {	
		String parentWindowHandle=driver.getWindowHandle();
		Set<String> windowHandles = driver.getWindowHandles();
		windowHandles.remove(parentWindowHandle);
		for(String handle:windowHandles) {
			driver.switchTo().window(handle);
				Thread.sleep(5000);
				if(driver.getTitle().contains(title)) {
					break;
				}
			
		}
		
		
	}
	
	
}
