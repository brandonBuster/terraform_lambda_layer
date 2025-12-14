import json
import numpy as np
import pandas as pd

def handler(event, context):
    arr = np.array([1, 2, 3, 4, 5])
    df = pd.DataFrame({"x": arr})
    return {
        "statusCode": 200,
        "body": json.dumps({
            "sum": int(df["x"].sum()),
            "shape": df.shape
        })
    }

if __name__ == "__main__":
    handler(None, None)