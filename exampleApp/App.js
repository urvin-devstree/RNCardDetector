import { Alert, Button, StyleSheet, View } from 'react-native';
import { scanPaymentCard } from 'react-native-card-detector';

const App = () => {

  const _onPressScanCardButton = async () => {
    try {
      const card = await scanPaymentCard({
        permission: { title: 'Camera Permission', description: 'ExampleApp would like to access your camera to scan a payment card.' }
      });
      console.log("card ==> ", card);
    } catch (error) {
      console.log('error ==> ', error);
    };
  };

  return (
    <View style={styles.mainContainer}>
      <Button title='Scan Card' onPress={_onPressScanCardButton} />
    </View>
  );
};

export default App;

const styles = StyleSheet.create({
  mainContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center'
  }
});