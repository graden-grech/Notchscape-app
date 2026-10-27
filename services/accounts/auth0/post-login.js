// Add to the Auth0 tenant's Login flow. This claim is signed by Auth0; a name,
// email supplied to our API, or editable user_metadata cannot set it.
exports.onExecutePostLogin = async (event, api) => {
  api.accessToken.setCustomClaim('https://notsoboringnotch.app/email_verified', event.user.email_verified === true);
};
