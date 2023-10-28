package pomRepo;

import org.openqa.selenium.WebDriver;
import org.openqa.selenium.WebElement;
import org.openqa.selenium.support.FindBy;
import org.openqa.selenium.support.PageFactory;

public class WelcomePage {
	
	public WelcomePage(WebDriver driver) {
		PageFactory.initElements(driver, this);
	}
	
	@FindBy(partialLinkText = "Log in")
	private WebElement loginLink;
	
	//business logic or action
	public void clickLoginLink() {
		loginLink.click();
	}

	public WebElement getLoginLink() {
		return loginLink;
	}

	public void setLoginLink(WebElement loginLink) {
		this.loginLink = loginLink;
	}
	
	@FindBy(partialLinkText = "BOOKS")
	WebElement headerBooksLink;
	
	@FindBy(partialLinkText = "Books")
	WebElement categoriesBooksLink;
	
	@FindBy(partialLinkText = "Facebook")
	 WebElement facebookLink;
	
	public void clickFaceBookLink() {
		facebookLink.click();
	}

	@FindBy(partialLinkText = "Twitter")
	 WebElement twitterLink;
	
	public void clickTwitterLink() {
		twitterLink.click();
	}
}
