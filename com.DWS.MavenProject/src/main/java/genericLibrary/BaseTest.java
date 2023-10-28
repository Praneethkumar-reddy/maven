package genericLibrary;

import java.time.Duration;

import org.openqa.selenium.WebDriver;
import org.openqa.selenium.chrome.ChromeDriver;
import org.openqa.selenium.firefox.FirefoxDriver;
import org.testng.annotations.AfterClass;
import org.testng.annotations.BeforeClass;
import org.testng.annotations.Optional;
import org.testng.annotations.Parameters;

public class BaseTest extends UtilityMethods {
	
	
	
	@Parameters("browserName")
	@BeforeClass
	public void browserSetup(@Optional("chrome") String browserName) {
		if(browserName.contains("chrome")) {
		System.setProperty("webdriver.chrome.driver", "./src/main/resources/Drivers/chromedriver.exe");
	    driver=new ChromeDriver(); 
	    }else if(browserName.contains("firefox")) {
	    	System.setProperty("webdriver.gecko.driver", "./Drivers/geckodriver.exe");
		    driver=new FirefoxDriver(); 
	    }else {
	    	System.out.println("Give valid browser name");
	    }
	    driver.manage().window().maximize();
		driver.manage().timeouts().implicitlyWait(Duration.ofSeconds(10));
		driver.get("http://demowebshop.tricentis.com/");
		initObjects();
	}
	@AfterClass
	public void browserTearDown() {
		//driver.quit();
		
	}

}
