package pomRepo;

import org.openqa.selenium.WebDriver;
import org.openqa.selenium.WebElement;
import org.openqa.selenium.support.FindBy;
import org.openqa.selenium.support.PageFactory;

public class LoginPage {
	
	public LoginPage(WebDriver driver) {
		PageFactory.initElements(driver, this);
	}
	
	@FindBy(id = "Email")
	private WebElement emailTextField; 
	
	public void enterEmail(String Email) {
		emailTextField.sendKeys(Email);
	}

	@FindBy(id = "Password")
	public WebElement passwordTextField;
}
