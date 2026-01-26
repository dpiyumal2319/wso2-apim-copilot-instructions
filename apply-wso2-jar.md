How to apply Java code changes to WSO2 server on the go?
========================================================

[![Tharika Madurapperuma](https://miro.medium.com/v2/resize:fill:64:64/1*KVgSLq5hyZFvy_RFVzxh6A.jpeg)](https://medium.com/?source=post_page---byline--caba252370---------------------------------------)

[Tharika Madurapperuma](https://medium.com/?source=post_page---byline--caba252370---------------------------------------)

4 min read

·

Jan 28, 2021

[nameless link](https://medium.com/m/signin?actionUrl=https%3A%2F%2Fmedium.com%2F_%2Fvote%2Fp%2Fcaba252370&operation=register&redirect=https%3A%2F%2Ftharika.medium.com%2Fhow-to-apply-java-code-changes-to-wso2-server-on-the-go-caba252370&user=Tharika+Madurapperuma&userId=e10a48267e46&source=---header_actions--caba252370---------------------clap_footer------------------)

--

4

[nameless link](https://medium.com/m/signin?actionUrl=https%3A%2F%2Fmedium.com%2F_%2Fbookmark%2Fp%2Fcaba252370&operation=register&redirect=https%3A%2F%2Ftharika.medium.com%2Fhow-to-apply-java-code-changes-to-wso2-server-on-the-go-caba252370&source=---header_actions--caba252370---------------------bookmark_footer------------------)

Listen

Share

Do you want to easily push changes to the running server without having to build the pack over again? Then this article is for you.

![Photo by Goran Ivos on Unsplash](https://miro.medium.com/v2/resize:fit:1400/format:webp/1*y-2A3st4DKxOtzesRgDETw.jpeg)

When you are actively building WSO2 Products, it will be a real hassle to do a simple java code change and rebuild the entire pack over again to see if the change you did actually works. Urgh it sucks! 😖

In this article I will show you how this can be easily overcome. It’s very simple.

I will take the code base of [WSO2 API Manager](https://wso2.com/api-manager/) for example here. Consider [this file](https://github.com/wso2/carbon-apimgt/blob/master/components/apimgt/org.wso2.carbon.apimgt.impl/src/main/java/org/wso2/carbon/apimgt/impl/jwt/JWTValidatorImpl.java) in the [**carbon-apimgt** repository](https://github.com/wso2/carbon-apimgt). Assume that you want to do a change in this file.

**Question:** When you have an already built WSO2 API Manager pack running in your machine, how can you apply the new fixes to this existing pack without building a new one?

### Let’s dive in and find the answer! 🙂

*   Now you can see that the **JWTValidatorImpl.java** file [here](https://github.com/wso2/carbon-apimgt/blob/master/components/apimgt/org.wso2.carbon.apimgt.impl/src/main/java/org/wso2/carbon/apimgt/impl/jwt/JWTValidatorImpl.java) is located inside the parent package **_org.wso2.carbon.apimgt.impl_**. Assume you did a change in this file. And you can see that if you build this **_impl_** package alone, you will get a **_.jar_** file in its **_target_** folder. This newly built .jar has your changes in it.
*   In the WSO2 API Manager pack(server) that you are running in your machine right now, all these component .jar files are packaged inside the **_<API-M_HOME>/repository/components/plugins_** folder.
*   You will be able to see a .jar file with a similar name like this in the plugins directory.

> org.wso2.carbon.apimgt.impl_9.30.98.SNAPSHOT.jar

*   This is the original .jar file of the **_impl_** package that you got when building the entire pack before. With this structure in place, there is an easier way to apply the new changes to the existing pack without building a new one. Can you see it now?
*   You guessed it right. But we are not going to replace this .jar with the new **_impl_** package .jar file. 🤓
*   You can see that there is another folder named **_patches_** in the **_<API-M_HOME>/repository/components_** directory. We are going to put the new **_impl_** jar into this as a **patch**.
*   Create a new folder named **_patch9999_** inside the patches folder and put the new .jar into it.
*   Rename the jar by replacing the **hyphens** with **underscore** and **dot** respectively as follows.

> org.wso2.carbon.apimgt.impl-9.30.98-SNAPSHOT.jar → **org.wso2.carbon.apimgt.impl_9.30.98.SNAPSHOT.jar**

*   Remember that the **version** of this jar should be the same as the original jar present in the **_plugins_** folder above. If the existing version is different from the newly built jar, you will have to rebuild the entire pack. No choice otherwise. 😐 The version can change if you fetched code from upstream after originally building the pack and later built the **_impl_** jar with your change. If an auto release has been triggered in the upstream git repository, the versions change automatically. Got it?
*   Now you must **restart the server** for the changes to take effect. When the server restarts, you will see the following log in the terminal to indicate that the patch changes are detected and applied.

```
INFO {org.wso2.carbon.server.extensions.PatchInstaller perform} — **Patch changes detected**
INFO {org.wso2.carbon.server.util.PatchUtils applyServicepacksAndPatches} — **Backed up plugins to patch0000**
INFO {org.wso2.carbon.server.util.PatchUtils checkMD5Checksum} — **Patch verification started**
INFO {org.wso2.carbon.server.util.PatchUtils checkMD5Checksum} — **Patch verification successfully completed**
```

*   What is this **“_Backed up plugins to patch0000”_** log above? After restarting the server, you will see a new folder created alongside patch9999. That is patch0000 to which the original jar files present in the plugins directory are backed up before applying the new change. Now the **_impl_** package jar file found inside the **_plugins_** folder is the newly changed jar. So do not delete the patch0000 folder as it is a backup of the original and you need it if you want to go back to the original state.
*   So now let’s see the steps in **summary** below.

> 1. Navigate to the parent package of the java file where you did the change and build it by executing the **mvn clean install -Dmaven.test.skip=true** command skipping the tests.
> 
> 2. Put the jar into **_patches9999_** folder inside **_<API-M_HOME>/repository/components/patches_** directory after renaming the file replacing hyphens with underscore and dot respectively.
> 
> 3. Restart the server.

Now you can make your development journey more effective with this approach. Isn’t it? 🙂

**Bonus Tip** **:** If you want to remove the change you just applied to the pack, simply remove the patch9999 folder and restart the server. In case if you have added multiple different jars to the patch9999 folder(based on your fix) and you need to revert the changes done to a specific jar(s) only, you can remove only the specific jar(s) from patch9999 and restart the APIM server.

Thank you for reading the article!

If you find any outdated content or issues with this article, please feel free to create an issue at **Developer Corner** Git repository [here](https://github.com/tharikaGitHub/developer-corner). Let’s grow together and help others in their journey too!

If you like this article please give it a clap. 🙂

Cheers!
